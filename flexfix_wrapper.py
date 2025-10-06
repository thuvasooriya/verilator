#!/usr/bin/env python3
"""
Wrapper for flexfix that adds file argument support for Zig build system.
The original flexfix reads from stdin and writes to stdout, but Zig's build
system needs to work with file paths.
"""

import argparse
import subprocess
import sys

def main():
    parser = argparse.ArgumentParser(description="flexfix wrapper with file argument support")
    parser.add_argument('--flexfix', required=True, help='Path to flexfix script')
    parser.add_argument('input_file', help='Input file to process')
    parser.add_argument('output_file', help='Output file to write')
    
    args = parser.parse_args()
    
    # Run flexfix with stdin/stdout redirection
    with open(args.input_file, 'r') as infile, open(args.output_file, 'w') as outfile:
        result = subprocess.run(
            ['python3', args.flexfix],
            stdin=infile,
            stdout=outfile,
            stderr=subprocess.PIPE,
            text=True
        )
        
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            sys.exit(result.returncode)

if __name__ == '__main__':
    main()
