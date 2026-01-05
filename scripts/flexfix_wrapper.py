#!/usr/bin/env python3
"""
Wrapper for upstream flexfix script to work with Zig build system.

WHY THIS EXISTS:
- Upstream flexfix (src/flexfix) is a stdin->stdout filter that post-processes
  flex output to fix various flex version bugs and compiler warnings
- Zig's build system (std.Build.Step.Run) has a bug with setStdIn + captureStdOut
  combination on macOS (fcopyfile errno 9 / EBADF)
- This wrapper bridges the gap by accepting file arguments and handling the
  stdin/stdout redirection in Python

WHAT FLEXFIX DOES:
- Fixes flex 2.6.x sign comparison warnings
- Fixes flex 2.5.x namespace and redefinition issues
- Removes deprecated 'register' keyword for C++17 compatibility
- Fixes various other flex version-specific bugs

USAGE IN BUILD:
  python3 flexfix_wrapper.py --flexfix <upstream/src/flexfix> <input.cpp> <output.cpp>

NOTE: We intentionally use upstream flexfix rather than reimplementing it,
so we automatically get any future bug fixes from Verilator maintainers.
"""

import argparse
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(
        description="flexfix wrapper with file argument support"
    )
    parser.add_argument("--flexfix", required=True, help="Path to flexfix script")
    parser.add_argument("input_file", help="Input file to process")
    parser.add_argument("output_file", help="Output file to write")

    args = parser.parse_args()

    # Run flexfix with stdin/stdout redirection
    with open(args.input_file, "r") as infile, open(args.output_file, "w") as outfile:
        result = subprocess.run(
            ["python3", args.flexfix],
            stdin=infile,
            stdout=outfile,
            stderr=subprocess.PIPE,
            text=True,
        )

        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            sys.exit(result.returncode)


if __name__ == "__main__":
    main()
