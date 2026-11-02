# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Lota's own C++ keeps every warning as an error; LÖVE's sources build
# with -w instead (ADR 001, section 1). Call this on every target that
# compiles Lota's own sources.
function(lota_strict_warnings target)
	target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
	# The MinGW spike: GCC 16 warns -Warray-bounds inside Ruby's own inline
	# functions (ruby/internal/fl_type.h:466, core/rarray.h:263) as Rice
	# inlines them, a false positive ("source object is likely at address
	# zero"); kept as a warning, not an error.
	if(MINGW)
		target_compile_options(${target} PRIVATE -Wno-error=array-bounds)
	endif()
endfunction()
