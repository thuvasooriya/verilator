#!/usr/bin/env python3
import sys
import re

if len(sys.argv) != 3:
    print("Usage: process_template.py <input> <output>", file=sys.stderr)
    sys.exit(1)

input_file = sys.argv[1]
output_file = sys.argv[2]

substitutions = {
    '@AR@': 'ar',
    '@CXX@': 'c++',
    '@OBJCACHE@': '',
    '@PERL@': 'perl',
    '@PYTHON3@': 'python3',
    '@CFG_WITH_CCWARN@': 'no',
    '@CFG_WITH_DEV_GCOV@': 'no',
    '@CFG_WITH_LONGTESTS@': 'no',
    '@CFG_CXX_VERSION@': 'c++20',
    '@CFG_CXXFLAGS_PROFILE@': '-pg',
    '@CFG_CXXFLAGS_STD@': '-std=c++20',
    '@CFG_CXXFLAGS_STD_NEWEST@': '-std=c++20',
    '@CFG_CXXFLAGS_NO_UNUSED@': '-Wno-unused-parameter -Wno-unused-variable',
    '@CFG_CXXFLAGS_WEXTRA@': '-Wextra',
    '@CFG_CXXFLAGS_COROUTINES@': '-fcoroutines',
    '@CFG_CXXFLAGS_PCH_I@': '-include',
    '@CFG_GCH_IF_CLANG@': '',
    '@CFG_LDFLAGS_VERILATED@': '',
    '@CFG_LDLIBS_THREADS@': '-lpthread',
    '@PACKAGE_NAME@': 'Verilator',
    '@PACKAGE_VERSION@': '5.41.0',
    '@VERILATOR_VERSION_INTEGER@': '5041000',
}

with open(input_file, 'r') as f:
    content = f.read()

for key, value in substitutions.items():
    content = content.replace(key, value)

with open(output_file, 'w') as f:
    f.write(content)
