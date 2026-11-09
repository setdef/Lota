# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Lota's own C++ keeps every warning as an error; LÖVE's sources build
# with -w instead (doc/contributors/design/engine.md). Call this on every target
# that compiles Lota's own sources.
function(lota_strict_warnings target)
	target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
endfunction()
