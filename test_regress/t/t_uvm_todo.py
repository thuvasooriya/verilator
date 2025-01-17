#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# Copyright 2024 by Wilson Snyder. This program is free software; you
# can redistribute it and/or modify it under the terms of either the GNU
# Lesser General Public License Version 3 or the Perl Artistic License
# Version 2.0.
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap
import multiprocessing

test.scenarios('vlt')

test.compile(v_flags2=["--timing", "+incdir+t/uvm", "t/t_uvm_todo.vlt"],
             make_flags=['-k -j ' + str(multiprocessing.cpu_count())],
             verilator_make_gmake=False)

#test.execute()

test.passes()
