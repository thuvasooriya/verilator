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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("verilator", .{});

    const verilator_exe = b.addExecutable(.{
        .name = "verilator_bin",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    const sources = [_][]const u8{
        "Verilator.cpp",
        "V3Active.cpp",
        "V3ActiveTop.cpp",
        "V3Assert.cpp",
        "V3AssertPre.cpp",
        "V3Ast.cpp",
        "V3AstNodes.cpp",
        "V3Begin.cpp",
        "V3Branch.cpp",
        "V3Broken.cpp",
        "V3CCtors.cpp",
        "V3CUse.cpp",
        "V3Case.cpp",
        "V3Cast.cpp",
        "V3Cfg.cpp",
        "V3CfgBuilder.cpp",
        "V3CfgLiveVariables.cpp",
        "V3Class.cpp",
        "V3Clean.cpp",
        "V3Clock.cpp",
        "V3Combine.cpp",
        "V3Common.cpp",
        "V3Control.cpp",
        "V3Coverage.cpp",
        "V3CoverageJoin.cpp",
        "V3Dead.cpp",
        "V3Delayed.cpp",
        "V3Depth.cpp",
        "V3DepthBlock.cpp",
        "V3Descope.cpp",
        "V3Dfg.cpp",
        "V3DfgAstToDfg.cpp",
        "V3DfgBreakCycles.cpp",
        "V3DfgCache.cpp",
        "V3DfgColorSCCs.cpp",
        "V3DfgCse.cpp",
        "V3DfgDataType.cpp",
        "V3DfgDecomposition.cpp",
        "V3DfgDfgToAst.cpp",
        "V3DfgOptimizer.cpp",
        "V3DfgPasses.cpp",
        "V3DfgPeephole.cpp",
        "V3DfgRegularize.cpp",
        "V3DfgSynthesize.cpp",
        "V3DiagSarif.cpp",
        "V3DupFinder.cpp",
        "V3EmitCBase.cpp",
        "V3EmitCConstPool.cpp",
        "V3EmitCFunc.cpp",
        "V3EmitCHeaders.cpp",
        "V3EmitCImp.cpp",
        "V3EmitCInlines.cpp",
        "V3EmitCMain.cpp",
        "V3EmitCMake.cpp",
        "V3EmitCModel.cpp",
        "V3EmitCPch.cpp",
        "V3EmitCSyms.cpp",
        "V3EmitMk.cpp",
        "V3EmitMkJson.cpp",
        "V3EmitV.cpp",
        "V3EmitXml.cpp",
        "V3Error.cpp",
        "V3ExecGraph.cpp",
        "V3Expand.cpp",
        "V3File.cpp",
        "V3FileLine.cpp",
        "V3Force.cpp",
        "V3Fork.cpp",
        "V3FuncOpt.cpp",
        "V3Gate.cpp",
        "V3Global.cpp",
        "V3Graph.cpp",
        "V3GraphAcyc.cpp",
        "V3GraphAlg.cpp",
        "V3GraphPathChecker.cpp",
        "V3GraphTest.cpp",
        "V3Hash.cpp",
        "V3Hasher.cpp",
        "V3HierBlock.cpp",
        "V3Inline.cpp",
        "V3Inst.cpp",
        "V3InstrCount.cpp",
        "V3Interface.cpp",
        "V3Life.cpp",
        "V3LifePost.cpp",
        "V3LinkCells.cpp",
        "V3LinkDot.cpp",
        "V3LinkInc.cpp",
        "V3LinkJump.cpp",
        "V3LinkLValue.cpp",
        "V3LinkLevel.cpp",
        "V3LinkParse.cpp",
        "V3LinkResolve.cpp",
        "V3Localize.cpp",
        "V3MergeCond.cpp",
        "V3Name.cpp",
        "V3Number.cpp",
        "V3OptionParser.cpp",
        "V3Options.cpp",
        "V3Order.cpp",
        "V3Os.cpp",
        "V3OrderGraphBuilder.cpp",
        "V3OrderMoveGraph.cpp",
        "V3OrderParallel.cpp",
        "V3OrderProcessDomains.cpp",
        "V3OrderSerial.cpp",
        "V3Param.cpp",
        "V3ParseGrammar.cpp",
        "V3ParseImp.cpp",
        "V3ParseLex.cpp",
        "V3PreProc.cpp",
        "V3PreShell.cpp",
        "V3Premit.cpp",
        "V3ProtectLib.cpp",
        "V3Randomize.cpp",
        "V3Reloop.cpp",
        "V3Sampled.cpp",
        "V3Sched.cpp",
        "V3SchedAcyclic.cpp",
        "V3SchedPartition.cpp",
        "V3SchedReplicate.cpp",
        "V3SchedTiming.cpp",
        "V3SchedVirtIface.cpp",
        "V3Scope.cpp",
        "V3Scoreboard.cpp",
        "V3Slice.cpp",
        "V3Split.cpp",
        "V3SplitAs.cpp",
        "V3SplitVar.cpp",
        "V3StackCount.cpp",
        "V3Stats.cpp",
        "V3StatsReport.cpp",
        "V3String.cpp",
        "V3Subst.cpp",
        "V3TSP.cpp",
        "V3Table.cpp",
        "V3Task.cpp",
        "V3ThreadPool.cpp",
        "V3Timing.cpp",
        "V3Trace.cpp",
        "V3TraceDecl.cpp",
        "V3Tristate.cpp",
        "V3Udp.cpp",
        "V3Undriven.cpp",
        "V3Unknown.cpp",
        "V3Unroll.cpp",
        "V3UnrollGen.cpp",
        "V3VariableOrder.cpp",
        "V3Waiver.cpp",
        "V3Width.cpp",
        "V3WidthCommit.cpp",
        "V3WidthSel.cpp",
    };

    for (sources) |src| {
        verilator_exe.addCSourceFile(.{
            .file = upstream.path(b.fmt("src/{s}", .{src})),
            .flags = &.{
                "-std=c++14",
                "-DYYDEBUG",
                "-Wall",
                "-Wextra",
                "-Wno-unused-parameter",
                "-Wno-shadow",
            },
        });
    }

    verilator_exe.addIncludePath(upstream.path("src"));
    verilator_exe.addIncludePath(upstream.path("include"));
    verilator_exe.addIncludePath(b.path("include"));
    verilator_exe.linkLibCpp();

    if (target.result.os.tag != .windows) {
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
    astgen_classes_cmd.addFileArg(b.path("astgen_wrapper.py"));
    astgen_classes_cmd.addArg("--astgen");
    astgen_classes_cmd.addFileArg(upstream.path("src/astgen"));
    astgen_classes_cmd.addArg("--source-dir");
    astgen_classes_cmd.addDirectoryArg(upstream.path("src"));
    astgen_classes_cmd.addArg("--astdef");
    astgen_classes_cmd.addArg("V3AstNodeDType.h");
    astgen_classes_cmd.addArg("--astdef");
    astgen_classes_cmd.addArg("V3AstNodeExpr.h");
    astgen_classes_cmd.addArg("--astdef");
    astgen_classes_cmd.addArg("V3AstNodeOther.h");
    astgen_classes_cmd.addArg("--astdef");
    astgen_classes_cmd.addArg("V3AstNodeStmt.h");
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
    astgen_const_cmd.addFileArg(b.path("astgen_wrapper.py"));
    astgen_const_cmd.addArg("--astgen");
    astgen_const_cmd.addFileArg(upstream.path("src/astgen"));
    astgen_const_cmd.addArg("--source-dir");
    astgen_const_cmd.addDirectoryArg(upstream.path("src"));
    astgen_const_cmd.addArg("--astdef");
    astgen_const_cmd.addArg("V3AstNodeDType.h");
    astgen_const_cmd.addArg("--astdef");
    astgen_const_cmd.addArg("V3AstNodeExpr.h");
    astgen_const_cmd.addArg("--astdef");
    astgen_const_cmd.addArg("V3AstNodeOther.h");
    astgen_const_cmd.addArg("--astdef");
    astgen_const_cmd.addArg("V3AstNodeStmt.h");
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
        .flags = &.{
            "-std=c++14",
            "-DYYDEBUG",
            "-Wall",
            "-Wextra",
            "-Wno-unused-parameter",
            "-Wno-shadow",
        },
    });

    // Add include paths to the astgen object
    astgen_const_obj.addIncludePath(upstream.path("src"));
    astgen_const_obj.addIncludePath(upstream.path("include"));
    astgen_const_obj.addIncludePath(b.path("include"));
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
    const flex_lexer = b.addSystemCommand(&[_][]const u8{
        "flex",
        "--c++",
        "-d",
        "-o",
    });
    const lexer_pregen = flex_lexer.addOutputFileArg("V3Lexer_pregen.yy.cpp");
    flex_lexer.addFileArg(upstream.path("src/verilog.l"));
    flex_lexer.step.dependOn(&bisonpre_cmd.step);

    // Step 2: Run flexfix wrapper to post-process
    const flexfix_lexer = b.addSystemCommand(&[_][]const u8{"python3"});
    flexfix_lexer.addFileArg(b.path("flexfix_wrapper.py"));
    flexfix_lexer.addArg("--flexfix");
    flexfix_lexer.addFileArg(upstream.path("src/flexfix"));
    flexfix_lexer.addFileArg(lexer_pregen);
    const lexer_output = flexfix_lexer.addOutputFileArg("V3Lexer.yy.cpp");

    const lexer_output_dir = lexer_output.dirname();
    verilator_exe.addIncludePath(lexer_output_dir);
    verilator_exe.step.dependOn(&flexfix_lexer.step);

    // Generate V3PreLex.yy.cpp using Flex + flexfix (two-step process)
    // Step 1: Run flex to generate intermediate file
    const flex_prelex = b.addSystemCommand(&[_][]const u8{
        "flex",
        "--c++",
        "-d",
        "-o",
    });
    const prelex_pregen = flex_prelex.addOutputFileArg("V3PreLex_pregen.yy.cpp");
    flex_prelex.addFileArg(upstream.path("src/V3PreLex.l"));
    flex_prelex.step.dependOn(&bisonpre_cmd.step);

    // Step 2: Run flexfix wrapper to post-process
    const flexfix_prelex = b.addSystemCommand(&[_][]const u8{"python3"});
    flexfix_prelex.addFileArg(b.path("flexfix_wrapper.py"));
    flexfix_prelex.addArg("--flexfix");
    flexfix_prelex.addFileArg(upstream.path("src/flexfix"));
    flexfix_prelex.addFileArg(prelex_pregen);
    const prelex_output = flexfix_prelex.addOutputFileArg("V3PreLex.yy.cpp");

    // Note: This file is #included by V3PreProc.cpp, not compiled separately
    const prelex_output_dir = prelex_output.dirname();
    verilator_exe.addIncludePath(prelex_output_dir);
    verilator_exe.step.dependOn(&flexfix_prelex.step);

    b.installArtifact(verilator_exe);

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
    coverage_exe.addIncludePath(b.path("include"));
    coverage_exe.step.dependOn(&config_files.step);

    // VlcMain.cpp is a unity build that includes other files
    coverage_exe.addCSourceFile(.{
        .file = upstream.path("src/VlcMain.cpp"),
        .flags = &.{
            "-std=c++14",
            "-DYYDEBUG",
            "-Wall",
            "-Wextra",
            "-Wno-unused-parameter",
            "-Wno-shadow",
        },
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

    // Install include files (verilated runtime support)
    const install_include = b.addInstallDirectory(.{
        .source_dir = upstream.path("include"),
        .install_dir = .prefix,
        .install_subdir = "include",
    });
    b.getInstallStep().dependOn(&install_include.step);

    const run_cmd = b.addRunArtifact(verilator_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run verilator");
    run_step.dependOn(&run_cmd.step);
}
