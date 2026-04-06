# How This Build System Works

This document explains how we compile Verilator using Zig's build system.

## The Problem

Verilator's upstream build uses autoconf + CMake with several code generation steps:

```
                    UPSTREAM BUILD
    
    verilog.y ──────> bison ──────> V3ParseBison.c/h
    verilog.l ──────> flex ───────> V3Lexer.yy.cpp
    V3PreLex.l ─────> flex ───────> V3PreLex.yy.cpp
    V3Ast*.h ───────> astgen ─────> V3Ast__gen_*.h + V3Const__gen.cpp
    
    Then: compile 155+ C++ files, link
```

Each tool (bison, flex, astgen) has quirks. Some outputs need post-processing. The generated files have complex interdependencies.

## The Solution

We wrap the upstream scripts instead of reimplementing them, and let Zig handle compilation:

```
                    ZIG BUILD PIPELINE
    
    ┌─────────────────────────────────────────────────────────┐
    │                                                         │
    │   build.zig.zon                                         │
    │        │                                                │
    │        ▼                                                │
    │   ┌─────────┐      ┌──────────────┐                     │
    │   │ Zig Fetch│ ───> │ Upstream src │                    │
    │   └─────────┘      └──────┬───────┘                     │
    │                           │                             │
    │        ┌──────────────────┼──────────────────┐          │
    │        ▼                  ▼                  ▼          │
    │   ┌─────────┐       ┌──────────┐       ┌─────────┐      │
    │   │  Bison  │       │   Flex   │       │ Astgen  │      │
    │   │(bisonpre)│      │(flexfix) │       │         │      │
    │   └────┬────┘       └────┬─────┘       └────┬────┘      │
    │        │                 │                  │           │
    │        ▼                 ▼                  ▼           │
    │   V3ParseBison      V3Lexer.yy         V3Ast__gen_*     │
    │   .c / .h           V3PreLex.yy        V3Const__gen     │
    │        │                 │                  │           │
    │        └────────┬────────┴──────────────────┘           │
    │                 ▼                                       │
    │         ┌──────────────┐                                │
    │         │  Zig C++     │                                │
    │         │  Compiler    │                                │
    │         └──────┬───────┘                                │
    │                ▼                                        │
    │         verilator_bin                                   │
    │                                                         │
    └─────────────────────────────────────────────────────────┘
```

## Key Insight: Unity Build Pattern

Verilator uses a "unity build" where generated parser/lexer files are `#include`d by wrapper files, not compiled separately:

```
    WRONG (duplicate symbols)          CORRECT (unity build)
    
    V3ParseBison.c ─┐                  V3ParseBison.c
           compile  │                        │
                    ├──> LINK ERROR          │ #include
    V3ParseGrammar  │                        ▼
           compile ─┘                  V3ParseGrammar.cpp ──> compile ──> OK
```

**Why?** The wrapper files need access to bison/flex internal symbols (`yydebug`, `yyparse`, etc.) which are file-scoped. Including the source is the only way.

### What Gets Included vs Compiled

```
    Generated File          Included By              Compiled?
    ─────────────────────────────────────────────────────────
    V3ParseBison.c    ───>  V3ParseGrammar.cpp       NO
    V3Lexer.yy.cpp    ───>  V3ParseLex.cpp           NO  
    V3PreLex.yy.cpp   ───>  V3PreProc.cpp            NO
    V3Const__gen.cpp  ───>  (none)                   YES
    V3Ast__gen_*.h    ───>  (many files)             NO (headers)
```

In `build.zig`, this means we add the generated file's directory to include paths instead of compiling it:

```zig
// Generate the file
const bison_output = bisonpre_cmd.addOutputFileArg("V3ParseBison.c");

// Add to include path (NOT compiled!)
verilator_exe.addIncludePath(bison_output.dirname());
```

## Wrapper Scripts

We use Python wrappers around upstream scripts:

| Script | Wraps | Why |
|--------|-------|-----|
| `astgen_wrapper.py` | `src/astgen` | astgen writes to cwd, needs temp dir setup |
| `flexfix_wrapper.py` | `src/flexfix` | Zig's stdin/stdout piping has macOS bug |
| `process_template.py` | autoconf | Simple `@VAR@` substitution |

**Philosophy:** Wrap, don't reimplement. Upstream bug fixes come free.

## Source Auto-Detection

Build.zig scans upstream `src/*.cpp` at build time:

```zig
fn isExcludedSource(name: []const u8) bool {
    // V3Const.cpp - content in generated V3Const__gen.cpp
    if (std.mem.eql(u8, name, "V3Const.cpp")) return true;
    // Coverage tool sources
    if (std.mem.startsWith(u8, name, "Vlc")) return true;
    // Test files (older versions)
    if (std.mem.endsWith(u8, name, "_test.cpp")) return true;
    return false;
}
```

This handles version differences automatically (e.g., `V3Number_test.cpp` exists in v5.020 but not v5.044).

## Version Compatibility

The build auto-detects AST definition files that vary by version:

```zig
const ast_node_files = [_][]const u8{
    "V3AstNodeDType.h",
    "V3AstNodeExpr.h",
    "V3AstNodeOther.h",
    "V3AstNodeStmt.h",  // Added in v5.040
};

// Only pass files that exist
for (ast_node_files) |file| {
    if (src_dir.access(file, .{})) |_| {
        cmd.addArg("--astdef");
        cmd.addArg(file);
    } else |_| {}
}
```

## Build Outputs

```
zig-out/
├── bin/
│   ├── verilator              # Perl wrapper (needs VERILATOR_ROOT)
│   ├── verilator_bin          # Main binary
│   ├── verilator_coverage     # Coverage wrapper
│   └── verilator_coverage_bin_dbg
└── include/
    └── verilated*.h           # Runtime headers
```

## Summary

1. **Fetch upstream** via `build.zig.zon`
2. **Generate** parser/lexer/AST files using upstream scripts (wrapped)
3. **Unity build** - include generated parser/lexer, don't compile separately
4. **Auto-detect** source files and version differences
5. **Compile** with Zig's C++ toolchain
6. **Cross-compile** to any Zig-supported target
