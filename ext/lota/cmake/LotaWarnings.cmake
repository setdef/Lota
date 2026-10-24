# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Lota's own C++ keeps every warning as an error; LÖVE's sources build
# with -w instead (ADR 001, section 1). Call this on every target that
# compiles Lota's own sources.
function(lota_strict_warnings target)
	target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
endfunction()
