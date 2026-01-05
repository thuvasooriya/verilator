#!/usr/bin/env python3
"""
Process autoconf-style template files (.in) by substituting @VAR@ placeholders.

WHY THIS EXISTS:
- Upstream Verilator uses autoconf which generates config values at configure time
- Templates like verilated.mk.in and verilated_config.h.in contain @VAR@ placeholders
- This script provides the same substitutions without requiring autoconf

WHAT IT PROCESSES:
- include/verilated.mk.in -> verilated.mk (Makefile for verilated designs)
- include/verilated_config.h.in -> verilated_config.h (runtime config header)

VERSION SOURCE:
- Extracts version from verilator URL tag in build.zig.zon (e.g., #v5.044 -> 5.044.0)

USAGE:
  python3 process_template.py <input.in> <output>
"""

import sys
import re
from pathlib import Path


def parse_build_zig_zon():
    """Extract version from verilator URL in build.zig.zon

    Handles both URL formats:
    - git+https://...#v5.044
    - git+https://...?ref=v5.042#<commit>
    """
    script_dir = Path(__file__).parent
    zon_path = script_dir.parent / "build.zig.zon"

    content = zon_path.read_text()

    # Try ?ref=v5.042 format first, then #v5.044 format
    url_match = re.search(r"\?ref=v(\d+\.\d+)", content)
    if not url_match:
        url_match = re.search(r"verilator#v(\d+\.\d+)", content)
    if not url_match:
        raise ValueError("Could not find verilator version tag in build.zig.zon URL")

    version_tag = url_match.group(1)  # e.g., "5.044"
    version = f"{version_tag}.0"  # e.g., "5.044.0"

    # Convert version to integer: 5.044 -> 5044000
    parts = version_tag.split(".")
    major = int(parts[0])
    minor = int(parts[1]) if len(parts) > 1 else 0
    version_int = major * 1000000 + minor * 1000

    return version, str(version_int)


if len(sys.argv) != 3:
    print("Usage: process_template.py <input> <output>", file=sys.stderr)
    sys.exit(1)

input_file = sys.argv[1]
output_file = sys.argv[2]

package_version, version_integer = parse_build_zig_zon()

substitutions = {
    "@AR@": "ar",
    "@CXX@": "c++",
    "@OBJCACHE@": "",
    "@PERL@": "perl",
    "@PYTHON3@": "python3",
    "@CFG_WITH_CCWARN@": "no",
    "@CFG_WITH_DEV_GCOV@": "no",
    "@CFG_WITH_LONGTESTS@": "no",
    "@CFG_CXX_VERSION@": "c++20",
    "@CFG_CXXFLAGS_PROFILE@": "-pg",
    "@CFG_CXXFLAGS_STD@": "-std=c++20",
    "@CFG_CXXFLAGS_STD_NEWEST@": "-std=c++20",
    "@CFG_CXXFLAGS_NO_UNUSED@": "-Wno-unused-parameter -Wno-unused-variable",
    "@CFG_CXXFLAGS_WEXTRA@": "-Wextra",
    "@CFG_CXXFLAGS_COROUTINES@": "-fcoroutines",
    "@CFG_CXXFLAGS_PCH_I@": "-include",
    "@CFG_GCH_IF_CLANG@": "",
    "@CFG_LDFLAGS_VERILATED@": "",
    "@CFG_LDLIBS_THREADS@": "-lpthread",
    "@PACKAGE_NAME@": "Verilator",
    "@PACKAGE_VERSION@": package_version,
    "@VERILATOR_VERSION_INTEGER@": version_integer,
}

with open(input_file, "r") as f:
    content = f.read()

for key, value in substitutions.items():
    content = content.replace(key, value)

with open(output_file, "w") as f:
    f.write(content)
