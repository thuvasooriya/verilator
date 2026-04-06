# Verilator Zig Build - Testing Documentation

## Overview

Verilator's test suite is located in `test_regress/` in the upstream repository. Tests are Python scripts that invoke the `driver.py` test harness.

## Test Infrastructure

### Requirements

- Python 3 with `distro` package (managed via `uv`)
- Perl (for verilator wrapper scripts)
- C++ compiler (for compiling verilated code)
- Make (for building test executables)

### Test Driver

The main test driver is `driver.py` located in `test_regress/`. It:
- Discovers and runs test files (`t/t_*.py`)
- Manages test scenarios (vlt, vltmt, dist, etc.)
- Handles parallel execution
- Reports pass/fail/skip status

## Test Scenarios

| Scenario | Flag | Description |
|----------|------|-------------|
| vlt | `--vlt` | Main Verilator tests, single-threaded simulation |
| vltmt | `--vltmt` | Multi-threaded Verilator tests |
| dist | `--dist` | Distribution/packaging tests |
| linter | subset of vlt | Lint-only tests (no compilation/simulation) |

### Scenario Selection in Tests

Each test file declares which scenarios it supports:
```python
test.scenarios('vlt')           # only vlt scenario
test.scenarios('linter')        # lint-only (subset of vlt)
test.scenarios('vlt', 'vltmt')  # both single and multi-threaded
```

## Running Tests

### Using justfile (Recommended)

```bash
# Basic commands
just test-self                    # Run selftest (basic functionality)
just test-lint                    # Run all lint tests (~140 tests)
just test-one t/t_lint_basic.py   # Run a single test

# Full scenarios
just test-vlt                     # All vlt scenario tests
just test-vltmt                   # All multi-threaded tests
just test-all                     # All scenarios (vlt + vltmt + dist)

# With options
just test-vlt --quiet             # Quiet mode (only show failures)
just test-parallel 8              # Use 8 parallel jobs
just test-vlt t/t_assert*.py      # Run subset of tests
```

### Direct driver.py Usage

```bash
cd ~/.cache/zig/p/<hash>/test_regress
VERILATOR_ROOT=/path/to/zig-out uv run --with distro python3 driver.py --vlt t/t_lint_basic.py
```

### Driver Options

| Option | Description |
|--------|-------------|
| `--vlt` | Run vlt scenario tests |
| `--vltmt` | Run multi-threaded tests |
| `--dist` | Run distribution tests |
| `--quiet` | Suppress output except failures |
| `-j N` | Use N parallel jobs (0=auto) |
| `--rerun` | Rerun failed tests |
| `--stop` | Stop on first failure |
| `--golden` | Update golden output files |

## Test Categories

### By Count (v5.044)
- Total test files: ~3360
- Lint tests: ~140
- Assert tests: ~58
- Coverage tests: ~53

### Common Test Prefixes

| Prefix | Description |
|--------|-------------|
| `t_lint_*` | Linting/warning tests |
| `t_assert_*` | Assertion tests |
| `t_cover_*` | Coverage tests |
| `t_trace_*` | Waveform tracing tests |
| `t_flag_*` | Command-line flag tests |
| `t_gen_*` | Generate block tests |
| `t_mem_*` | Memory tests |
| `t_interface_*` | Interface tests |

## Test File Structure

Each test is a Python file in `t/`:
```python
#!/usr/bin/env python3
import vltest_bootstrap

test.scenarios('vlt')  # Which scenarios to run

# For lint-only tests
test.lint()

# For compile+simulate tests
test.compile()
test.execute()

test.passes()
```

### Associated Files

- `t_foo.py` - Test script
- `t_foo.v` - Verilog source (if needed)
- `t_foo.out` - Expected output (for error tests)
- `t_foo.cpp` - C++ testbench (if needed)

## Known Issues

### Zig Runtime Safety Failures

Some tests fail because Zig's runtime safety checks catch undefined behavior in upstream Verilator C++ code:

```
thread panic: shift exponent 32 is too large for 32-bit type 'int'
```

These are NOT bugs in our build - they're latent bugs in upstream Verilator that Zig catches. Examples:
- `t_lint_width_genfor.py` - integer shift overflow
- `t_lint_width_shift_bad.py` - shift overflow

### Tests That Skip

Some tests skip due to missing capabilities:
- Coroutines not available
- Not in a git repository
- SystemC not available

## Test Output Directories

Tests create output in `test_regress/obj_<scenario>/`:
- `obj_vlt/` - vlt scenario outputs
- `obj_vltmt/` - vltmt scenario outputs
- `obj_dist/` - dist scenario outputs

Each test creates a subdirectory: `obj_vlt/t_test_name/`

## Debugging Failed Tests

1. Run single test without `--quiet`:
   ```bash
   just test-one t/t_failing_test.py
   ```

2. Check test log:
   ```bash
   cat ~/.cache/zig/p/<hash>/test_regress/obj_vlt/t_failing_test/vlt_compile.log
   ```

3. Run verilator manually:
   ```bash
   just lint test_regress/t/t_failing_test.v
   ```

## Adding Custom Tests

To test our build quickly:
```bash
# Create a simple test file
echo 'module test; endmodule' > /tmp/test.v

# Run lint
just lint /tmp/test.v
```
