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
  python3 process_template.py <input.in> <output> --cxx <compiler> [--ar <archiver>]
"""

import argparse
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


def is_clang_based(cxx: str) -> bool:
    """Check if compiler is clang-based (zig c++, clang++, etc.)"""
    return "zig" in cxx.lower() or "clang" in cxx.lower()


parser = argparse.ArgumentParser(description="Process autoconf templates")
parser.add_argument("input", help="Input template file (.in)")
parser.add_argument("output", help="Output file")
parser.add_argument(
    "--cxx", default="c++", help="C++ compiler (e.g., zig c++, clang++, g++)"
)
parser.add_argument("--ar", default="ar", help="Archiver (e.g., zig ar, llvm-ar, ar)")
args = parser.parse_args()

package_version, version_integer = parse_build_zig_zon()

# Detect compiler type for flags
is_clang = is_clang_based(args.cxx)

# Clang uses -std=c++20 for coroutines, GCC uses -fcoroutines
coroutines_flag = "" if is_clang else "-fcoroutines"
# Clang uses .gch suffix for precompiled headers
gch_if_clang = ".gch" if is_clang else ""

substitutions = {
    "@AR@": args.ar,
    "@CXX@": args.cxx,
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
    "@CFG_CXXFLAGS_COROUTINES@": coroutines_flag,
    "@CFG_CXXFLAGS_PCH_I@": "-include",
    "@CFG_GCH_IF_CLANG@": gch_if_clang,
    "@CFG_LDFLAGS_VERILATED@": "",
    "@CFG_LDLIBS_THREADS@": "-lpthread",
    "@PACKAGE_NAME@": "Verilator",
    "@PACKAGE_VERSION@": package_version,
    "@VERILATOR_VERSION_INTEGER@": version_integer,
}

with open(args.input, "r") as f:
    content = f.read()

for key, value in substitutions.items():
    content = content.replace(key, value)

# For verilated.mk, add runtime compiler detection and env var overrides
if args.output.endswith("verilated.mk"):
    # Add a header block that handles env var overrides properly
    # Make has implicit CXX/AR variables, so we need VERILATOR_CXX/VERILATOR_AR
    # that users can set to override the defaults
    env_override_block = """
######################################################################
# Compiler override via environment variables
# Set VERILATOR_CXX and VERILATOR_AR to override the defaults
# Example: VERILATOR_CXX=g++ VERILATOR_AR=ar make

VERILATOR_CXX ?= {cxx}
VERILATOR_AR ?= {ar}
""".format(cxx=args.cxx, ar=args.ar)

    # Replace the tool definitions with our override mechanism
    content = re.sub(
        r"^AR = .+\nCXX = .+\nLINK = .+",
        env_override_block.strip()
        + "\n\nAR = $(VERILATOR_AR)\nCXX = $(VERILATOR_CXX)\nLINK = $(VERILATOR_CXX)",
        content,
        flags=re.MULTILINE,
    )

    # Add runtime compiler detection block after CFG_LDLIBS_THREADS
    # This must be AFTER all static CFG_* definitions so it can override them
    compiler_detection = """
######################################################################
# Runtime compiler detection - adjusts flags based on actual CXX value
# These override the static CFG_* values above when compiler changes

# Detect if using zig compiler (for linker flag compatibility)
VK_IS_ZIG := $(if $(findstring zig,$(CXX)),1,)

# Detect if using clang-based compiler (zig, clang++, Apple clang)
VK_IS_CLANG := $(if $(or $(findstring zig,$(CXX)),$(findstring clang,$(CXX))),1,)

# GCC needs -fcoroutines for coroutine support, clang/zig use -std=c++20
ifeq ($(VK_IS_CLANG),)
  CFG_CXXFLAGS_COROUTINES = -fcoroutines
else
  CFG_CXXFLAGS_COROUTINES =
endif

# Clang uses .gch suffix for precompiled headers
ifeq ($(VK_IS_CLANG),1)
  CFG_GCH_IF_CLANG = .gch
else
  CFG_GCH_IF_CLANG =
endif
"""

    # Insert after CFG_LDLIBS_THREADS line (after all static CFG_* definitions)
    insert_marker = "CFG_LDLIBS_THREADS ="
    insert_pos = content.find(insert_marker)
    if insert_pos != -1:
        # Find end of that line
        line_end = content.find("\n", insert_pos)
        if line_end != -1:
            content = (
                content[: line_end + 1] + compiler_detection + content[line_end + 1 :]
            )

    # Replace macOS -U flag handling with runtime detection
    # Original: LDFLAGS += -Wl,-U,__Z15vl_time_stamp64v,-U,__Z13sc_time_stampv
    # For zig: LDFLAGS += -Wl,-undefined,dynamic_lookup
    # For others: keep original
    macos_ldflags_old = (
        "  LDFLAGS += -Wl,-U,__Z15vl_time_stamp64v,-U,__Z13sc_time_stampv"
    )
    macos_ldflags_new = """  # Zig linker doesn't support -Wl,-U, use -undefined dynamic_lookup instead
  ifeq ($(VK_IS_ZIG),1)
    LDFLAGS += -Wl,-undefined,dynamic_lookup
  else
    LDFLAGS += -Wl,-U,__Z15vl_time_stamp64v,-U,__Z13sc_time_stampv
  endif"""
    content = content.replace(macos_ldflags_old, macos_ldflags_new)

with open(args.output, "w") as f:
    f.write(content)
