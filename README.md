# verilator

zig-based build system and setup for [verilator](https://github.com/verilator/verilator)

## version compatibility

tested range: **v5.018 - v5.044** (and likely newer)

## quick start

```bash
zig build -Doptimize=ReleaseFast

./zig-out/bin/verilator --version
./zig-out/bin/verilator --lint-only your_design.v
```

## requirements

### build dependencies

| dependency  | notes                         |
| ----------- | ----------------------------- |
| zig 0.15.2+ | build system and c++ compiler |
| python 3    | wrapper scripts               |
| bison 2.3+  | parser generator              |

### runtime dependencies

| dependency   | notes                                |
| ------------ | ------------------------------------ |
| perl         | verilator wrapper scripts            |
| make         | building verilated designs           |
| c++ compiler | compiling verilated code (see below) |

## build options

| option         | default | description                                           |
| -------------- | ------- | ----------------------------------------------------- |
| `-Doptimize`   | Debug   | ReleaseFast, ReleaseSafe, ReleaseSmall                |
| `-Dtarget`     | native  | cross-compile target (e.g., `aarch64-linux-gnu`)      |
| `-Duse-zig-cc` | true    | use `zig c++`/`zig ar` for verilated code compilation |
| `-Dcxx`        | (auto)  | override c++ compiler (e.g., `clang++`, `g++`)        |
| `-Dar`         | (auto)  | override archiver (e.g., `llvm-ar`, `ar`)             |

### compiler selection

by default, verilated designs use `zig c++` as the compiler. this provides:

- cross-platform builds without msvc/mingw on windows
- consistent c++20/coroutines support
- single toolchain

to use system compiler:

```bash
zig build -Duse-zig-cc=false    # uses system c++ and ar
```

to use a specific compiler:

```bash
zig build -Dcxx=clang++ -Dar=llvm-ar
zig build -Dcxx=g++ -Dar=ar
```

> [!NOTE]
> `-Dcxx`/`-Dar` take precedence over `-Duse-zig-cc`

### runtime compiler override

the generated `verilated.mk` defaults to `zig c++` but supports runtime override:

```bash
# override when building verilated designs
VERILATOR_CXX=g++ VERILATOR_AR=ar make -f Vdesign.mk

# or export for the session
export VERILATOR_CXX=clang++
export VERILATOR_AR=llvm-ar
make -f Vdesign.mk
```

the makefile automatically detects compiler type (zig/clang/gcc) and adjusts:
- coroutine flags (`-fcoroutines` for gcc)
- precompiled header suffix (`.gch` for clang)
- macos linker flags (`-undefined dynamic_lookup` for zig)

## building

```bash
zig build
```

### switch verilator version

```bash
zig fetch --save=verilator "git+https://github.com/verilator/verilator#v5.042"
zig build
```

### cross-compilation

```bash
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseFast
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast
```

### supported targets:

- `x86_64-linux-gnu`, `aarch64-linux-gnu`
- `x86_64-macos`, `aarch64-macos`
- `x86_64-windows-gnu`, `aarch64-windows-gnu`

## output structure

```
zig-out/
├── bin/
│   ├── verilator              # perl wrapper (entry point)
│   ├── verilator_bin          # main compiler binary
│   ├── verilator_coverage     # coverage tool wrapper
│   └── ...
└── include/
    ├── verilated.h            # runtime headers
    ├── verilated.mk           # makefile for verilated designs
    └── vltstd/                # standard library
```

