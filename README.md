# Verilator Zig Build

Zig-based build system for [Verilator](https://github.com/verilator/verilator), the fast SystemVerilog/Verilog simulator.

## Version Compatibility

Tested range: **v5.018 - v5.044** (and likely newer)

## Quick Start

```bash
zig build -Doptimize=ReleaseFast

./zig-out/bin/verilator --version
./zig-out/bin/verilator --lint-only your_design.v
```

## Requirements

| Dependency  | Build | Runtime | Notes               |
| ----------- | ----- | ------- | ------------------- |
| Zig 0.15.2+ | Yes   | No      |                     |
| Python 3    | Yes   | No      | For wrapper scripts |
| Bison 2.3+  | Yes   | No      | Parser generator    |
| Perl        | No    | Yes     | Verilator wrapper   |

Flex is built via Zig module (no system dependency).

## Building

```bash
zig build
```

```bash
# if you want to switch versions
zig fetch --save=verilator "git+https://github.com/verilator/verilator#v5.042"
```

```bash
# cross-compilation
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseFast
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast
```

## License

Verilator: LGPL-3.0-only OR Artistic-2.0
