# Verilator Zig Build

## Quick Start

```bash
zig build -Doptimize=ReleaseFast

./zig-out/bin/verilator --version
./zig-out/bin/verilator --help
./zig-out/bin/verilator --lint-only your_design.v

./zig-out/bin/verilator_coverage --help
```

## Requirements

**Build-time:**

- Zig 0.15.1+
- Python 3
- Bison 2.3+
- Flex 2.5.4+

**Runtime:**

- Perl (for wrapper script)
- C++ standard library

## Build Process

The build system automatically:

1. **Generates config headers** (`generate.zig`)
   - `config_package.h` - Package metadata
   - `config_rev.h` - Git version from upstream dependency URL

2. **Runs Bison** (generates parser from upstream)
   - `verilog.y` → `V3ParseBison.c`, `V3ParseBison.h`
   - Used via `#include` by `V3ParseGrammar.cpp` (unity build)

3. **Runs Flex** (generates lexers from upstream)
   - `verilog.l` → `V3Lexer.yy.cpp` (included by `V3ParseLex.cpp`)
   - `V3PreLex.l` → `V3PreLex.yy.cpp` (included by `V3PreProc.cpp`)
   - Post-processed with `flexfix_wrapper.py` (uses upstream flexfix)

4. **Runs Astgen** (generates AST code from upstream)
   - Creates 24 header files (`V3Ast__gen_*.h`, `V3Dfg__gen_*.h`)
   - Creates `V3Const__gen.cpp` (compiled separately)
   - Uses `astgen_wrapper.py` to invoke upstream astgen script

5. **Compiles everything**
   - 153 upstream C++ files
   - 1 generated C++ file (`V3Const__gen.cpp`)
   - Links with libc++

6. **Installs**
   - `bin/verilator` - Perl wrapper
   - `bin/verilator_bin` - Compiled binary
   - `bin/verilator_coverage` - Perl wrapper
   - `bin/verilator_coverage_bin_dbg` - Coverage binary
   - `include/` - Runtime support files

## Project Structure

```
.
├── build.zig              # Main build system
├── generate.zig           # Config header generation library
├── build.zig.zon          # Verilator source dependency
├── astgen_wrapper.py      # Wrapper for upstream astgen
├── flexfix_wrapper.py     # Wrapper for upstream flexfix
└── include/
    └── FlexLexer.h        # Local flex header
```

## Unity Build Pattern

Verilator uses "unity builds" where some generated files are `#include`d rather than compiled separately.

This allows wrapper code to access internal bison/flex symbols:

- `V3ParseBison.c` → included by `V3ParseGrammar.cpp`
- `V3Lexer.yy.cpp` → included by `V3ParseLex.cpp`
- `V3PreLex.yy.cpp` → included by `V3PreProc.cpp`

**Exception**: `V3Const__gen.cpp` is compiled as a separate object.

## Build Outputs

| Metric             | Debug    | ReleaseFast |
| ------------------ | -------- | ----------- |
| verilator_bin      | 145 MB   | ~15 MB      |
| verilator_coverage | 3.9 MB   | ~800 KB     |
| Build Time         | ~2-3 min | ~5-10 min   |

## Testing

```bash
# Version check
$ ./zig-out/bin/verilator --version
Verilator 5.41.0 rev b4d064d

# Coverage tool
$ ./zig-out/bin/verilator_coverage --version
Verilator 5.41.0 rev b4d064d
```

## Updating Verilator Version

Edit `build.zig.zon`:

```zig
.verilator = .{
    .url = "https://github.com/verilator/verilator/archive/<commit>.tar.gz",
    .hash = "...", // Run zig build to get the hash
},
```

Then run `zig build` and fix any compilation errors from API changes.

## Implementation Notes

- All generation commands use upstream Verilator sources via wrappers
- Config files generated from `build.zig.zon` dependency URL
- Generated files written to `.zig-cache`
- Unity build pattern: some generated files are `#include`d instead of compiled separately
- Coverage tool (`VlcMain.cpp`) is a simple unity build with no generation dependencies

## License

Verilator is licensed under LGPL-3.0-only OR Artistic-2.0.
This follows the same terms.
