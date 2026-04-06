# verilator zig build - justfile

set shell := ["bash", "-cu"]

# extract upstream hash from build.zig.zon dynamically

upstream_hash := `awk '/\.verilator = /{f=1} f && /\.hash =/{match($0, /"[^"]+"/); print substr($0, RSTART+1, RLENGTH-2); exit}' build.zig.zon`
upstream_cache := "~/.cache/zig/p/" + upstream_hash
test_regress := upstream_cache + "/test_regress"

default:
    just --list

# build verilator
build:
    zig build

# build in release mode
release:
    zig build -Doptimize=ReleaseFast

# clean build artifacts
clean:
    rm -rf .zig-cache zig-out

# run verilator --version
version: build
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out ./zig-out/bin/verilator_bin --version

# run verilator --help
help-verilator: build
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out ./zig-out/bin/verilator_bin --help

# lint a verilog file (usage: just lint path/to/file.v)
lint file: build
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out ./zig-out/bin/verilator_bin --lint-only {{ file }}

# run a single test (usage: just test-one t/t_lint_basic.py)
test-one test_file:
    cd {{ test_regress }} && \
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out \
    uv run --with distro python3 driver.py --vlt {{ test_file }}

# run all lint tests (quick sanity check)
test-lint:
    cd {{ test_regress }} && \
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out \
    uv run --with distro python3 driver.py --vlt t/t_lint_*.py --quiet

# run selftest (basic functionality test)
test-self:
    cd {{ test_regress }} && \
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out \
    uv run --with distro python3 driver.py --vlt t/t_a3_selftest.py

# run vlt scenario tests (main verilator tests, no SystemC)
test-vlt *args='':
    cd {{ test_regress }} && \
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out \
    uv run --with distro python3 driver.py --vlt {{ args }}

# run vltmt scenario tests (multithreaded tests)
test-vltmt *args='':
    cd {{ test_regress }} && \
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out \
    uv run --with distro python3 driver.py --vltmt {{ args }}

# run full test suite (vlt + vltmt + dist scenarios)
test-all *args='':
    cd {{ test_regress }} && \
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out \
    uv run --with distro python3 driver.py --vlt --vltmt --dist {{ args }}

# run all vlt tests in parallel with auto job count (main test command)
test-full:
    cd {{ test_regress }} && \
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out \
    uv run --with distro python3 driver.py --vlt -j 0 --quiet --rerun

# run tests with parallel jobs (usage: just test-parallel 8)
test-parallel jobs='0' *args='':
    cd {{ test_regress }} && \
    VERILATOR_ROOT={{ justfile_directory() }}/zig-out \
    uv run --with distro python3 driver.py --vlt -j {{ jobs }} {{ args }}

# show upstream test directory
show-test-dir:
    @echo {{ test_regress }}

# list available test files
list-tests pattern='t_*.py':
    @ls {{ test_regress }}/t/{{ pattern }} | head -50

# count tests by category
count-tests:
    @echo "Total test files: $(ls {{ test_regress }}/t/t_*.py | wc -l | tr -d ' ')"
    @echo "Lint tests: $(ls {{ test_regress }}/t/t_lint_*.py 2>/dev/null | wc -l | tr -d ' ')"
    @echo "Assert tests: $(ls {{ test_regress }}/t/t_assert*.py 2>/dev/null | wc -l | tr -d ' ')"
    @echo "Coverage tests: $(ls {{ test_regress }}/t/t_cover*.py 2>/dev/null | wc -l | tr -d ' ')"

# show current verilator version from build.zig.zon
show-version:
    @grep -oE '(ref=v|\#v)[0-9.]+' build.zig.zon | head -1 | sed 's/.*v//' | xargs -I{} echo {}.0
