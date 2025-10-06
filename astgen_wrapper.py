#!/usr/bin/env python3
"""
Wrapper for astgen that adds --output-dir support for Zig build system.
Runs astgen in a temp directory then copies outputs to the specified location.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(
        description="astgen wrapper with output directory support"
    )
    parser.add_argument(
        "--output-dir", required=True, help="Output directory for generated files"
    )
    parser.add_argument("--astgen", required=True, help="Path to astgen script")
    parser.add_argument(
        "--source-dir", required=True, help="Verilator source directory"
    )
    parser.add_argument("--astdef", action="append", help="AST definition files")
    parser.add_argument("--dfgdef", action="append", help="DFG definition files")
    parser.add_argument(
        "astgen_args", nargs="*", help="Additional arguments to pass to astgen"
    )

    args = parser.parse_args()

    # Create output directory if needed
    os.makedirs(args.output_dir, exist_ok=True)

    # Create temp directory for astgen to work in
    with tempfile.TemporaryDirectory() as tmpdir:
        # astgen needs to run in a directory where it can create files
        # Copy Verilator.cpp (for stage ordering)
        src_files = ["Verilator.cpp"]
        for src_file in src_files:
            src_path = os.path.join(args.source_dir, src_file)
            if os.path.exists(src_path):
                shutil.copy(src_path, tmpdir)

        # Also need to copy all .h, .cpp, .y files for read_refs
        for ext in ["*.h", "*.cpp", "*.y"]:
            for filepath in os.listdir(args.source_dir):
                if filepath.endswith(ext.replace("*", "")):
                    src_path = os.path.join(args.source_dir, filepath)
                    if os.path.isfile(src_path):
                        try:
                            shutil.copy(src_path, tmpdir)
                        except:
                            pass  # Skip if file can't be copied

        # Run astgen in temp directory
        cmd = [
            "python3",
            args.astgen,
            "-I",
            tmpdir,
        ]

        # Add astdef files
        if args.astdef:
            for astdef in args.astdef:
                cmd.extend(["--astdef", astdef])

        # Add dfgdef files
        if args.dfgdef:
            for dfgdef in args.dfgdef:
                cmd.extend(["--dfgdef", dfgdef])

        cmd.extend(args.astgen_args)

        # Change to temp dir to run astgen
        result = subprocess.run(cmd, cwd=tmpdir, capture_output=True, text=True)

        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            print(result.stdout)
            sys.exit(result.returncode)

        # Copy all generated files to output directory
        for filename in os.listdir(tmpdir):
            if (
                filename.startswith("V3Ast__gen_")
                or filename.startswith("V3Dfg__gen_")
                or filename.endswith("__gen.cpp")
                or filename.endswith("__gen.h")
            ):
                src = os.path.join(tmpdir, filename)
                dst = os.path.join(args.output_dir, filename)
                shutil.copy(src, dst)
                print(f"Generated: {filename}")


if __name__ == "__main__":
    main()
