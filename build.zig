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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("verilator", .{});

    // Get flex dependency - built for host to run during build
    const flex_dep = b.dependency("flex", .{});
    const flex_exe = flex_dep.artifact("flex");
    const flex_upstream = flex_dep.builder.dependency("flex", .{});

    // Release build by default (use verilator_bin_dbg for debug)
    const release_optimize = if (optimize == .Debug) .ReleaseFast else optimize;

    const verilator_exe = b.addExecutable(.{
        .name = "verilator_bin",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = release_optimize,
        }),
    });

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

        verilator_exe.addCSourceFile(.{
            .file = upstream.path(b.fmt("src/{s}", .{name})),
            .flags = cpp_flags,
        });
    }

    verilator_exe.addIncludePath(upstream.path("src"));
    verilator_exe.addIncludePath(upstream.path("include"));
    verilator_exe.addIncludePath(flex_upstream.path("src")); // FlexLexer.h
    verilator_exe.linkLibCpp();

    if (target.result.os.tag == .windows) {
        // Windows API libraries for memory info and crypto
        verilator_exe.linkSystemLibrary("psapi"); // GetProcessMemoryInfo
        verilator_exe.linkSystemLibrary("bcrypt"); // BCryptGenRandom
    } else {
        verilator_exe.linkSystemLibrary("pthread");
    }

    // Auto-generate platform-specific config files before building
    const config_files = b.addWriteFiles();
    generate.addConfigFiles(b, config_files);
    verilator_exe.addIncludePath(config_files.getDirectory());
    verilator_exe.step.dependOn(&config_files.step);

    // Generate AST header files using astgen wrapper (--classes mode)
    const astgen_classes_cmd = b.addSystemCommand(&[_][]const u8{
        "python3",
    });
    astgen_classes_cmd.addFileArg(b.path("scripts/astgen_wrapper.py"));
    astgen_classes_cmd.addArg("--astgen");
    astgen_classes_cmd.addFileArg(upstream.path("src/astgen"));
    astgen_classes_cmd.addArg("--source-dir");
    astgen_classes_cmd.addDirectoryArg(upstream.path("src"));
    // Auto-detect which AST node files exist (V3AstNodeStmt.h added in v5.040)
    addAstDefArgs(astgen_classes_cmd, src_dir, upstream, b);
    astgen_classes_cmd.addArg("--dfgdef");
    astgen_classes_cmd.addArg("V3DfgVertices.h");
    astgen_classes_cmd.addArg("--output-dir");
    const astgen_classes_output = astgen_classes_cmd.addOutputDirectoryArg("astgen_classes");
    astgen_classes_cmd.addArg("--");
    astgen_classes_cmd.addArg("--classes");
    verilator_exe.step.dependOn(&astgen_classes_cmd.step);
    verilator_exe.addIncludePath(astgen_classes_output);

    // Generate V3Const__gen.cpp using astgen wrapper
    const astgen_const_cmd = b.addSystemCommand(&[_][]const u8{
        "python3",
    });
    astgen_const_cmd.addFileArg(b.path("scripts/astgen_wrapper.py"));
    astgen_const_cmd.addArg("--astgen");
    astgen_const_cmd.addFileArg(upstream.path("src/astgen"));
    astgen_const_cmd.addArg("--source-dir");
    astgen_const_cmd.addDirectoryArg(upstream.path("src"));
    // Auto-detect which AST node files exist (V3AstNodeStmt.h added in v5.040)
    addAstDefArgs(astgen_const_cmd, src_dir, upstream, b);
    astgen_const_cmd.addArg("--dfgdef");
    astgen_const_cmd.addArg("V3DfgVertices.h");
    astgen_const_cmd.addArg("--output-dir");
    const astgen_const_output = astgen_const_cmd.addOutputDirectoryArg("astgen_const");
    astgen_const_cmd.addArg("--");
    astgen_const_cmd.addArg("V3Const.cpp");

    // Compile the AST-generated file as a separate object
    const astgen_const_obj = b.addObject(.{
        .name = "V3Const__gen",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    // CRITICAL: Ensure the object compilation waits for astgen generation
    astgen_const_obj.step.dependOn(&astgen_const_cmd.step);
    astgen_const_obj.step.dependOn(&astgen_classes_cmd.step);

    astgen_const_obj.addCSourceFile(.{
        .file = astgen_const_output.path(b, "V3Const__gen.cpp"),
        .flags = cpp_flags,
    });

    // Add include paths to the astgen object
    astgen_const_obj.addIncludePath(upstream.path("src"));
    astgen_const_obj.addIncludePath(upstream.path("include"));
    astgen_const_obj.addIncludePath(flex_upstream.path("src"));
    astgen_const_obj.addIncludePath(astgen_classes_output);
    astgen_const_obj.addIncludePath(config_files.getDirectory());
    astgen_const_obj.step.dependOn(&config_files.step);
    astgen_const_obj.linkLibCpp();

    // Link the astgen object into the main executable
    verilator_exe.addObject(astgen_const_obj);

    // Generate V3ParseBison.c/h using bisonpre + Bison (must be before Flex to provide YYSTYPE)
    // NOTE: V3ParseBison.c is NOT compiled separately - it's #included by V3ParseGrammar.cpp
    const bisonpre_cmd = b.addSystemCommand(&[_][]const u8{
        "python3",
    });
    bisonpre_cmd.addFileArg(upstream.path("src/bisonpre"));
    bisonpre_cmd.addArg("--yacc");
    bisonpre_cmd.addArg("bison");
    bisonpre_cmd.addArg("-d");
    bisonpre_cmd.addArg("-v");
    bisonpre_cmd.addArg("-o");
    const bison_c_output = bisonpre_cmd.addOutputFileArg("V3ParseBison.c");
    bisonpre_cmd.addFileArg(upstream.path("src/verilog.y"));

    // Add bison output directory to include paths so V3ParseGrammar.cpp can #include it
    const bison_output_dir = bison_c_output.dirname();
    verilator_exe.addIncludePath(bison_output_dir);

    // Ensure compilation waits for bison generation
    verilator_exe.step.dependOn(&bisonpre_cmd.step);

    // Generate V3Lexer.yy.cpp using Flex + flexfix (depends on Bison for YYSTYPE)
    // Note: This file is #included by V3ParseLex.cpp, not compiled separately
    // Step 1: Run flex to generate intermediate file
    const flex_lexer = b.addRunArtifact(flex_exe);
    flex_lexer.addArgs(&.{ "--c++", "-d", "-o" });
    const lexer_pregen = flex_lexer.addOutputFileArg("V3Lexer_pregen.yy.cpp");
    flex_lexer.addFileArg(upstream.path("src/verilog.l"));
    flex_lexer.step.dependOn(&bisonpre_cmd.step);

    // Step 2: Run flexfix wrapper to post-process
    const flexfix_lexer = b.addSystemCommand(&[_][]const u8{"python3"});
    flexfix_lexer.addFileArg(b.path("scripts/flexfix_wrapper.py"));
    flexfix_lexer.addArg("--flexfix");
    flexfix_lexer.addFileArg(upstream.path("src/flexfix"));
    flexfix_lexer.addFileArg(lexer_pregen);
    const lexer_output = flexfix_lexer.addOutputFileArg("V3Lexer.yy.cpp");

    const lexer_output_dir = lexer_output.dirname();
    verilator_exe.addIncludePath(lexer_output_dir);
    verilator_exe.step.dependOn(&flexfix_lexer.step);

    // Generate V3PreLex.yy.cpp using Flex + flexfix (two-step process)
    // Step 1: Run flex to generate intermediate file
    const flex_prelex = b.addRunArtifact(flex_exe);
    flex_prelex.addArgs(&.{ "--c++", "-d", "-o" });
    const prelex_pregen = flex_prelex.addOutputFileArg("V3PreLex_pregen.yy.cpp");
    flex_prelex.addFileArg(upstream.path("src/V3PreLex.l"));
    flex_prelex.step.dependOn(&bisonpre_cmd.step);

    // Step 2: Run flexfix wrapper to post-process
    const flexfix_prelex = b.addSystemCommand(&[_][]const u8{"python3"});
    flexfix_prelex.addFileArg(b.path("scripts/flexfix_wrapper.py"));
    flexfix_prelex.addArg("--flexfix");
    flexfix_prelex.addFileArg(upstream.path("src/flexfix"));
    flexfix_prelex.addFileArg(prelex_pregen);
    const prelex_output = flexfix_prelex.addOutputFileArg("V3PreLex.yy.cpp");

    // Note: This file is #included by V3PreProc.cpp, not compiled separately
    const prelex_output_dir = prelex_output.dirname();
    verilator_exe.addIncludePath(prelex_output_dir);
    verilator_exe.step.dependOn(&flexfix_prelex.step);

    b.installArtifact(verilator_exe);

    // Build verilator_bin_dbg (debug version for --debug flag)
    // Always built with Debug optimization regardless of -Doptimize flag
    const verilator_dbg_exe = b.addExecutable(.{
        .name = "verilator_bin_dbg",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = .Debug,
        }),
    });

    // Re-iterate source files for debug build
    var src_dir_dbg = std.fs.openDirAbsolute(src_path, .{ .iterate = true }) catch |err| {
        std.debug.print("Failed to open upstream src directory for debug build: {}\n", .{err});
        return;
    };
    defer src_dir_dbg.close();

    var iter_dbg = src_dir_dbg.iterate();
    while (iter_dbg.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (!std.mem.endsWith(u8, name, ".cpp")) continue;
        if (isExcludedSource(name)) continue;

        verilator_dbg_exe.addCSourceFile(.{
            .file = upstream.path(b.fmt("src/{s}", .{name})),
            .flags = cpp_flags,
        });
    }

    verilator_dbg_exe.addIncludePath(upstream.path("src"));
    verilator_dbg_exe.addIncludePath(upstream.path("include"));
    verilator_dbg_exe.addIncludePath(flex_upstream.path("src"));
    verilator_dbg_exe.linkLibCpp();

    if (target.result.os.tag == .windows) {
        verilator_dbg_exe.linkSystemLibrary("psapi");
        verilator_dbg_exe.linkSystemLibrary("bcrypt");
    } else {
        verilator_dbg_exe.linkSystemLibrary("pthread");
    }

    // Share generated files with release build
    verilator_dbg_exe.addIncludePath(config_files.getDirectory());
    verilator_dbg_exe.step.dependOn(&config_files.step);
    verilator_dbg_exe.step.dependOn(&astgen_classes_cmd.step);
    verilator_dbg_exe.addIncludePath(astgen_classes_output);
    verilator_dbg_exe.step.dependOn(&bisonpre_cmd.step);
    verilator_dbg_exe.addIncludePath(bison_output_dir);
    verilator_dbg_exe.step.dependOn(&flexfix_lexer.step);
    verilator_dbg_exe.addIncludePath(lexer_output_dir);
    verilator_dbg_exe.step.dependOn(&flexfix_prelex.step);
    verilator_dbg_exe.addIncludePath(prelex_output_dir);

    // Build debug version of V3Const__gen object
    const astgen_const_obj_dbg = b.addObject(.{
        .name = "V3Const__gen_dbg",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = .Debug,
        }),
    });
    astgen_const_obj_dbg.step.dependOn(&astgen_const_cmd.step);
    astgen_const_obj_dbg.step.dependOn(&astgen_classes_cmd.step);
    astgen_const_obj_dbg.addCSourceFile(.{
        .file = astgen_const_output.path(b, "V3Const__gen.cpp"),
        .flags = cpp_flags,
    });
    astgen_const_obj_dbg.addIncludePath(upstream.path("src"));
    astgen_const_obj_dbg.addIncludePath(upstream.path("include"));
    astgen_const_obj_dbg.addIncludePath(flex_upstream.path("src"));
    astgen_const_obj_dbg.addIncludePath(astgen_classes_output);
    astgen_const_obj_dbg.addIncludePath(config_files.getDirectory());
    astgen_const_obj_dbg.step.dependOn(&config_files.step);
    astgen_const_obj_dbg.linkLibCpp();

    verilator_dbg_exe.addObject(astgen_const_obj_dbg);

    b.installArtifact(verilator_dbg_exe);

    // Build verilator_coverage_bin_dbg (coverage tool)
    const coverage_exe = b.addExecutable(.{
        .name = "verilator_coverage_bin_dbg",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    coverage_exe.linkLibCpp();
    coverage_exe.addIncludePath(config_files.getDirectory());
    coverage_exe.addIncludePath(upstream.path("include"));
    coverage_exe.addIncludePath(upstream.path("src"));
    coverage_exe.addIncludePath(flex_upstream.path("src"));
    coverage_exe.step.dependOn(&config_files.step);

    if (target.result.os.tag == .windows) {
        coverage_exe.linkSystemLibrary("psapi");
        coverage_exe.linkSystemLibrary("bcrypt");
    }

    // VlcMain.cpp is a unity build that includes other files
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
    const verilated_mk = generate.generateVerilatedMk(b, upstream);
    const install_verilated_mk = b.addInstallFile(
        verilated_mk,
        "include/verilated.mk",
    );
    b.getInstallStep().dependOn(&install_verilated_mk.step);

    // Generate and install verilated_config.h from template
    const verilated_config_h = generate.generateVerilatedConfigH(b, upstream);
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
}
