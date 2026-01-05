const std = @import("std");
const builtin = @import("builtin");
const generate = @import("generate.zig");

comptime {
    const build_zon = @import("build.zig.zon");
    const required_zig = std.SemanticVersion.parse(build_zon.minimum_zig_version) catch unreachable;
    const current_zig = builtin.zig_version;

    if (current_zig.order(required_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Zig version {}.{}.{} is too old. This project requires Zig >= {}.{}.{}", .{ current_zig.major, current_zig.minor, current_zig.patch, required_zig.major, required_zig.minor, required_zig.patch }));
    }
}

// Check if a program exists in PATH (uses Zig's cross-platform PATH lookup)
fn findProgram(b: *std.Build, name: []const u8) bool {
    _ = b.findProgram(&.{name}, &.{}) catch return false;
    return true;
}

fn checkBuildDependencies(b: *std.Build) void {
    var has_error = false;
    var has_warning = false;

    // Build-time required (bison, python3)
    const build_required = [_][]const u8{ "bison", "python3" };
    for (build_required) |prog| {
        if (!findProgram(b, prog)) {
            if (!has_error) {
                std.debug.print("\n\x1b[31mError: Missing required build dependencies:\x1b[0m\n", .{});
                has_error = true;
            }
            std.debug.print("  - {s}\n", .{prog});
        }
    }

    if (has_error) {
        std.debug.print("\nInstall missing dependencies and try again.\n", .{});
        std.debug.print("  macOS:  brew install bison python3\n", .{});
        std.debug.print("  Ubuntu: apt install bison python3\n\n", .{});
        std.process.exit(1);
    }

    // Runtime dependencies (warn only)
    const runtime_deps = [_]struct { name: []const u8, desc: []const u8 }{
        .{ .name = "perl", .desc = "verilator wrapper scripts" },
        .{ .name = "make", .desc = "building verilated designs" },
    };
    for (runtime_deps) |dep| {
        if (!findProgram(b, dep.name)) {
            if (!has_warning) {
                std.debug.print("\n\x1b[33mWarning: Missing runtime dependencies:\x1b[0m\n", .{});
                has_warning = true;
            }
            std.debug.print("  - {s} ({s})\n", .{ dep.name, dep.desc });
        }
    }
    if (has_warning) {
        std.debug.print("\n", .{});
    }
}

const cpp_flags = &[_][]const u8{
    "-std=c++14",
    "-DYYDEBUG",
    "-Wall",
    "-Wextra",
    "-Wno-unused-parameter",
    "-Wno-shadow",
    "-fno-sanitize=undefined", // Disable UBSAN - upstream has undefined behavior
    "-fwrapv", // Wrap signed integer overflow instead of UB
};

// Generated files from bison, flex, astgen - these are target-independent
// and can be shared across all target builds
const GeneratedFiles = struct {
    config_dir: std.Build.LazyPath,
    astgen_classes_dir: std.Build.LazyPath,
    astgen_const_dir: std.Build.LazyPath,
    bison_dir: std.Build.LazyPath,
    lexer_dir: std.Build.LazyPath,
    prelex_dir: std.Build.LazyPath,
    flexlexer_dir: std.Build.LazyPath, // FlexLexer.h from flex upstream
    // Steps that must complete before compilation
    config_step: *std.Build.Step,
    astgen_classes_step: *std.Build.Step,
    astgen_const_step: *std.Build.Step,
    bison_step: *std.Build.Step,
    lexer_step: *std.Build.Step,
    prelex_step: *std.Build.Step,
};

// Files excluded from verilator_bin compilation:
// - V3Const.cpp: Content included in generated V3Const__gen.cpp by astgen
// - Vlc*.cpp: Coverage tool sources (VlcMain.cpp, VlcTop.cpp)
// - *_test.cpp: Test files (e.g., V3Number_test.cpp in older versions)
fn isExcludedSource(name: []const u8) bool {
    if (std.mem.eql(u8, name, "V3Const.cpp")) return true;
    if (std.mem.startsWith(u8, name, "Vlc")) return true;
    if (std.mem.endsWith(u8, name, "_test.cpp")) return true;
    return false;
}

// AST node definition files - detect which ones exist for version compatibility
// V3AstNodeStmt.h was added in v5.040, older versions only have DType/Expr/Other
const ast_node_files = [_][]const u8{
    "V3AstNodeDType.h",
    "V3AstNodeExpr.h",
    "V3AstNodeOther.h",
    "V3AstNodeStmt.h", // Added in v5.040
};

fn addAstDefArgs(cmd: *std.Build.Step.Run, src_dir: std.fs.Dir, upstream: *std.Build.Dependency, b: *std.Build) void {
    for (ast_node_files) |file| {
        if (src_dir.access(file, .{})) |_| {
            cmd.addArg("--astdef");
            cmd.addArg(file);
        } else |_| {
            // File doesn't exist in this version, skip it
            _ = upstream;
            _ = b;
        }
    }
}

// Create all generated files (bison, flex, astgen, config) - runs once on host
fn createGeneratedFiles(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    flex_dep: *std.Build.Dependency,
) GeneratedFiles {
    const flex_exe = flex_dep.artifact("flex");
    const flex_upstream = flex_dep.builder.dependency("flex", .{});

    // Open src directory to detect available files
    const src_path = upstream.path("src").getPath(b);
    var src_dir = std.fs.openDirAbsolute(src_path, .{ .iterate = true }) catch |err| {
        std.debug.print("Failed to open upstream src directory: {}\n", .{err});
        @panic("Cannot open upstream src directory");
    };
    defer src_dir.close();

    // Config headers
    const config_files = b.addWriteFiles();
    generate.addConfigFiles(b, config_files);

    // Astgen --classes (AST headers)
    const astgen_classes_cmd = b.addSystemCommand(&[_][]const u8{"python3"});
    astgen_classes_cmd.addFileArg(b.path("scripts/astgen_wrapper.py"));
    astgen_classes_cmd.addArg("--astgen");
    astgen_classes_cmd.addFileArg(upstream.path("src/astgen"));
    astgen_classes_cmd.addArg("--source-dir");
    astgen_classes_cmd.addDirectoryArg(upstream.path("src"));
    addAstDefArgs(astgen_classes_cmd, src_dir, upstream, b);
    astgen_classes_cmd.addArg("--dfgdef");
    astgen_classes_cmd.addArg("V3DfgVertices.h");
    astgen_classes_cmd.addArg("--output-dir");
    const astgen_classes_output = astgen_classes_cmd.addOutputDirectoryArg("astgen_classes");
    astgen_classes_cmd.addArg("--");
    astgen_classes_cmd.addArg("--classes");

    // Astgen V3Const__gen.cpp
    const astgen_const_cmd = b.addSystemCommand(&[_][]const u8{"python3"});
    astgen_const_cmd.addFileArg(b.path("scripts/astgen_wrapper.py"));
    astgen_const_cmd.addArg("--astgen");
    astgen_const_cmd.addFileArg(upstream.path("src/astgen"));
    astgen_const_cmd.addArg("--source-dir");
    astgen_const_cmd.addDirectoryArg(upstream.path("src"));
    addAstDefArgs(astgen_const_cmd, src_dir, upstream, b);
    astgen_const_cmd.addArg("--dfgdef");
    astgen_const_cmd.addArg("V3DfgVertices.h");
    astgen_const_cmd.addArg("--output-dir");
    const astgen_const_output = astgen_const_cmd.addOutputDirectoryArg("astgen_const");
    astgen_const_cmd.addArg("--");
    astgen_const_cmd.addArg("V3Const.cpp");

    // Bison (V3ParseBison.c/h)
    const bisonpre_cmd = b.addSystemCommand(&[_][]const u8{"python3"});
    bisonpre_cmd.addFileArg(upstream.path("src/bisonpre"));
    bisonpre_cmd.addArg("--yacc");
    bisonpre_cmd.addArg("bison");
    bisonpre_cmd.addArg("-d");
    bisonpre_cmd.addArg("-v");
    bisonpre_cmd.addArg("-o");
    const bison_c_output = bisonpre_cmd.addOutputFileArg("V3ParseBison.c");

    bisonpre_cmd.addFileArg(upstream.path("src/verilog.y"));

    // Flex lexer (V3Lexer.yy.cpp)
    const flex_lexer = b.addRunArtifact(flex_exe);
    flex_lexer.addArgs(&.{ "--c++", "-d", "-o" });
    const lexer_pregen = flex_lexer.addOutputFileArg("V3Lexer_pregen.yy.cpp");
    flex_lexer.addFileArg(upstream.path("src/verilog.l"));
    flex_lexer.step.dependOn(&bisonpre_cmd.step);

    const flexfix_lexer = b.addSystemCommand(&[_][]const u8{"python3"});
    flexfix_lexer.addFileArg(b.path("scripts/flexfix_wrapper.py"));
    flexfix_lexer.addArg("--flexfix");
    flexfix_lexer.addFileArg(upstream.path("src/flexfix"));
    flexfix_lexer.addFileArg(lexer_pregen);
    const lexer_output = flexfix_lexer.addOutputFileArg("V3Lexer.yy.cpp");

    // Flex prelex (V3PreLex.yy.cpp)
    const flex_prelex = b.addRunArtifact(flex_exe);
    flex_prelex.addArgs(&.{ "--c++", "-d", "-o" });
    const prelex_pregen = flex_prelex.addOutputFileArg("V3PreLex_pregen.yy.cpp");
    flex_prelex.addFileArg(upstream.path("src/V3PreLex.l"));
    flex_prelex.step.dependOn(&bisonpre_cmd.step);

    const flexfix_prelex = b.addSystemCommand(&[_][]const u8{"python3"});
    flexfix_prelex.addFileArg(b.path("scripts/flexfix_wrapper.py"));
    flexfix_prelex.addArg("--flexfix");
    flexfix_prelex.addFileArg(upstream.path("src/flexfix"));
    flexfix_prelex.addFileArg(prelex_pregen);
    const prelex_output = flexfix_prelex.addOutputFileArg("V3PreLex.yy.cpp");

    return .{
        .config_dir = config_files.getDirectory(),
        .astgen_classes_dir = astgen_classes_output,
        .astgen_const_dir = astgen_const_output,
        .bison_dir = bison_c_output.dirname(),
        .lexer_dir = lexer_output.dirname(),
        .prelex_dir = prelex_output.dirname(),
        .flexlexer_dir = flex_upstream.path("src"),
        .config_step = &config_files.step,
        .astgen_classes_step = &astgen_classes_cmd.step,
        .astgen_const_step = &astgen_const_cmd.step,
        .bison_step = &bisonpre_cmd.step,
        .lexer_step = &flexfix_lexer.step,
        .prelex_step = &flexfix_prelex.step,
    };
}

// Add verilator source files and configure executable with generated file deps
fn configureVerilatorExe(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    upstream: *std.Build.Dependency,
    gen: GeneratedFiles,
) void {
    // Auto-detect source files from upstream src/ directory
    const src_path = upstream.path("src").getPath(b);
    var src_dir = std.fs.openDirAbsolute(src_path, .{ .iterate = true }) catch |err| {
        std.debug.print("Failed to open upstream src directory: {}\n", .{err});
        return;
    };
    defer src_dir.close();

    var iter = src_dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (!std.mem.endsWith(u8, name, ".cpp")) continue;
        if (isExcludedSource(name)) continue;

        exe.addCSourceFile(.{
            .file = upstream.path(b.fmt("src/{s}", .{name})),
            .flags = cpp_flags,
        });
    }

    exe.addIncludePath(upstream.path("src"));
    exe.addIncludePath(upstream.path("include"));
    exe.addIncludePath(gen.flexlexer_dir);
    exe.linkLibCpp();

    // Add generated file include paths and dependencies
    exe.addIncludePath(gen.config_dir);
    exe.addIncludePath(gen.astgen_classes_dir);
    exe.addIncludePath(gen.bison_dir);
    exe.addIncludePath(gen.lexer_dir);
    exe.addIncludePath(gen.prelex_dir);
    exe.step.dependOn(gen.config_step);
    exe.step.dependOn(gen.astgen_classes_step);
    exe.step.dependOn(gen.bison_step);
    exe.step.dependOn(gen.lexer_step);
    exe.step.dependOn(gen.prelex_step);
}

// Create V3Const__gen object for a specific target/optimize
fn createAstgenConstObj(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    upstream: *std.Build.Dependency,
    gen: GeneratedFiles,
    name_suffix: []const u8,
) *std.Build.Step.Compile {
    const obj = b.addObject(.{
        .name = b.fmt("V3Const__gen{s}", .{name_suffix}),
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    obj.step.dependOn(gen.astgen_const_step);
    obj.step.dependOn(gen.astgen_classes_step);
    obj.step.dependOn(gen.config_step);
    obj.addCSourceFile(.{
        .file = gen.astgen_const_dir.path(b, "V3Const__gen.cpp"),
        .flags = cpp_flags,
    });
    obj.addIncludePath(upstream.path("src"));
    obj.addIncludePath(upstream.path("include"));
    obj.addIncludePath(gen.flexlexer_dir);
    obj.addIncludePath(gen.astgen_classes_dir);
    obj.addIncludePath(gen.config_dir);
    obj.linkLibCpp();
    return obj;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Compiler options for verilated code (what users compile their designs with)
    const cxx_option = b.option([]const u8, "cxx", "C++ compiler for verilated code (e.g., clang++, g++)");
    const ar_option = b.option([]const u8, "ar", "Archiver for verilated code (e.g., llvm-ar)");
    const use_zig_cc = b.option(bool, "use-zig-cc", "Use zig c++/ar for verilated code (default: true)") orelse true;
    const cxx = cxx_option orelse if (use_zig_cc) "zig c++" else "c++";
    const ar = ar_option orelse if (use_zig_cc) "zig ar" else "ar";

    checkBuildDependencies(b);

    const upstream = b.dependency("verilator", .{});
    const flex_dep = b.dependency("flex", .{});

    // Generate files once - shared across all targets
    const gen = createGeneratedFiles(b, upstream, flex_dep);

    // Release build by default
    const release_optimize = if (optimize == .Debug) .ReleaseFast else optimize;

    // verilator_bin (release)
    const verilator_exe = b.addExecutable(.{
        .name = "verilator_bin",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = release_optimize,
        }),
    });
    configureVerilatorExe(b, verilator_exe, upstream, gen);
    if (target.result.os.tag == .windows) {
        verilator_exe.linkSystemLibrary("psapi");
        verilator_exe.linkSystemLibrary("bcrypt");
    } else {
        verilator_exe.linkSystemLibrary("pthread");
    }
    verilator_exe.addObject(createAstgenConstObj(b, target, release_optimize, upstream, gen, ""));
    b.installArtifact(verilator_exe);

    // verilator_bin_dbg (debug)
    const verilator_dbg_exe = b.addExecutable(.{
        .name = "verilator_bin_dbg",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = .Debug,
        }),
    });
    configureVerilatorExe(b, verilator_dbg_exe, upstream, gen);
    if (target.result.os.tag == .windows) {
        verilator_dbg_exe.linkSystemLibrary("psapi");
        verilator_dbg_exe.linkSystemLibrary("bcrypt");
    } else {
        verilator_dbg_exe.linkSystemLibrary("pthread");
    }
    verilator_dbg_exe.addObject(createAstgenConstObj(b, target, .Debug, upstream, gen, "_dbg"));
    b.installArtifact(verilator_dbg_exe);

    // verilator_coverage_bin_dbg
    const coverage_exe = b.addExecutable(.{
        .name = "verilator_coverage_bin_dbg",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    coverage_exe.linkLibCpp();
    coverage_exe.addIncludePath(gen.config_dir);
    coverage_exe.addIncludePath(upstream.path("include"));
    coverage_exe.addIncludePath(upstream.path("src"));
    coverage_exe.addIncludePath(gen.flexlexer_dir);
    coverage_exe.step.dependOn(gen.config_step);
    if (target.result.os.tag == .windows) {
        coverage_exe.linkSystemLibrary("psapi");
        coverage_exe.linkSystemLibrary("bcrypt");
    }
    coverage_exe.addCSourceFile(.{
        .file = upstream.path("src/VlcMain.cpp"),
        .flags = cpp_flags,
    });
    b.installArtifact(coverage_exe);

    // Install Perl wrapper scripts
    const verilator_script = b.addInstallFile(
        upstream.path("bin/verilator"),
        "bin/verilator",
    );
    b.getInstallStep().dependOn(&verilator_script.step);

    const coverage_script = b.addInstallFile(
        upstream.path("bin/verilator_coverage"),
        "bin/verilator_coverage",
    );
    b.getInstallStep().dependOn(&coverage_script.step);

    const includer_script = b.addInstallFile(
        upstream.path("bin/verilator_includer"),
        "bin/verilator_includer",
    );
    b.getInstallStep().dependOn(&includer_script.step);

    const ccache_report_script = b.addInstallFile(
        upstream.path("bin/verilator_ccache_report"),
        "bin/verilator_ccache_report",
    );
    b.getInstallStep().dependOn(&ccache_report_script.step);

    // Install include files (verilated runtime support)
    const install_include = b.addInstallDirectory(.{
        .source_dir = upstream.path("include"),
        .install_dir = .prefix,
        .install_subdir = "include",
    });
    b.getInstallStep().dependOn(&install_include.step);

    // Generate and install verilated.mk from template
    const verilated_mk = generate.generateVerilatedMk(b, upstream, cxx, ar);
    const install_verilated_mk = b.addInstallFile(
        verilated_mk,
        "include/verilated.mk",
    );
    b.getInstallStep().dependOn(&install_verilated_mk.step);

    // Generate and install verilated_config.h from template
    const verilated_config_h = generate.generateVerilatedConfigH(b, upstream, cxx);
    const install_verilated_config_h = b.addInstallFile(
        verilated_config_h,
        "include/verilated_config.h",
    );
    b.getInstallStep().dependOn(&install_verilated_config_h.step);

    const run_cmd = b.addRunArtifact(verilator_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run verilator");
    run_step.dependOn(&run_cmd.step);

    // CI step: cross-compile for all targets and create release archives
    const ci_step = b.step("ci", "Build release archives for all targets");
    addCiTargets(b, ci_step, upstream, flex_dep, gen);
}

const ci_targets = [_][]const u8{
    "x86_64-linux-gnu",
    "aarch64-linux-gnu",
    "x86_64-macos",
    "aarch64-macos",
    "x86_64-windows-gnu",
    "aarch64-windows-gnu",
};

fn addCiTargets(
    b: *std.Build,
    ci_step: *std.Build.Step,
    upstream: *std.Build.Dependency,
    flex_dep: *std.Build.Dependency,
    gen: GeneratedFiles,
) void {
    const build_zon = @import("build.zig.zon");
    const version = generate.extractVersionFromUrl(build_zon.dependencies.verilator.url) orelse "0.0.0";

    // Write version file for CI to read
    const write_version = b.addWriteFiles();
    _ = write_version.add("version", version);
    const install_version = b.addInstallFile(write_version.getDirectory().path(b, "version"), "version");
    ci_step.dependOn(&install_version.step);

    const install_path = b.getInstallPath(.prefix, ".");
    _ = flex_dep;

    for (ci_targets) |target_str| {
        const target = b.resolveTargetQuery(std.Target.Query.parse(
            .{ .arch_os_abi = target_str },
        ) catch @panic("invalid target"));

        const is_windows = target.result.os.tag == .windows;

        // Create verilator_bin for this target
        const verilator_exe = b.addExecutable(.{
            .name = "verilator_bin",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = .ReleaseFast,
            }),
        });
        configureVerilatorExe(b, verilator_exe, upstream, gen);
        if (is_windows) {
            verilator_exe.linkSystemLibrary("psapi");
            verilator_exe.linkSystemLibrary("bcrypt");
        } else {
            verilator_exe.linkSystemLibrary("pthread");
        }
        verilator_exe.addObject(createAstgenConstObj(b, target, .ReleaseFast, upstream, gen, b.fmt("_{s}", .{target_str})));

        // Create verilator_coverage_bin_dbg for this target
        const coverage_exe = b.addExecutable(.{
            .name = "verilator_coverage_bin_dbg",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = .ReleaseFast,
            }),
        });
        coverage_exe.linkLibCpp();
        coverage_exe.addIncludePath(gen.config_dir);
        coverage_exe.addIncludePath(upstream.path("include"));
        coverage_exe.addIncludePath(upstream.path("src"));
        coverage_exe.addIncludePath(gen.flexlexer_dir);
        coverage_exe.step.dependOn(gen.config_step);
        if (is_windows) {
            coverage_exe.linkSystemLibrary("psapi");
            coverage_exe.linkSystemLibrary("bcrypt");
        }
        coverage_exe.addCSourceFile(.{
            .file = upstream.path("src/VlcMain.cpp"),
            .flags = cpp_flags,
        });

        // Install to target-specific bin directory
        const target_bin_dir: std.Build.InstallDir = .{ .custom = b.fmt("{s}/bin", .{target_str}) };
        const install_exe = b.addInstallArtifact(verilator_exe, .{
            .dest_dir = .{ .override = target_bin_dir },
        });
        const install_cov = b.addInstallArtifact(coverage_exe, .{
            .dest_dir = .{ .override = target_bin_dir },
        });

        // Install scripts and includes to target dir
        const install_verilator_script = b.addInstallFile(
            upstream.path("bin/verilator"),
            b.fmt("{s}/bin/verilator", .{target_str}),
        );
        const install_coverage_script = b.addInstallFile(
            upstream.path("bin/verilator_coverage"),
            b.fmt("{s}/bin/verilator_coverage", .{target_str}),
        );
        const install_include = b.addInstallDirectory(.{
            .source_dir = upstream.path("include"),
            .install_dir = .{ .custom = target_str },
            .install_subdir = "include",
        });

        // Create archive after all installs complete
        const archive_name = b.fmt("verilator-{s}-{s}", .{ version, target_str });

        if (is_windows) {
            const zip = b.addSystemCommand(&.{
                "zip",                                                             "-r",
                b.pathJoin(&.{ install_path, b.fmt("{s}.zip", .{archive_name}) }), target_str,
            });
            zip.cwd = .{ .cwd_relative = install_path };
            zip.step.dependOn(&install_exe.step);
            zip.step.dependOn(&install_cov.step);
            zip.step.dependOn(&install_verilator_script.step);
            zip.step.dependOn(&install_coverage_script.step);
            zip.step.dependOn(&install_include.step);
            ci_step.dependOn(&zip.step);
        } else {
            const tar = b.addSystemCommand(&.{
                "tar",                                                                "-czvf",
                b.pathJoin(&.{ install_path, b.fmt("{s}.tar.gz", .{archive_name}) }), target_str,
            });
            tar.cwd = .{ .cwd_relative = install_path };
            tar.step.dependOn(&install_exe.step);
            tar.step.dependOn(&install_cov.step);
            tar.step.dependOn(&install_verilator_script.step);
            tar.step.dependOn(&install_coverage_script.step);
            tar.step.dependOn(&install_include.step);
            ci_step.dependOn(&tar.step);
        }
    }
}
