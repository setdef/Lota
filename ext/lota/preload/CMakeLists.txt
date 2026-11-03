# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# The preloader, Windows' stand-in for an rpath (require "lota/preload",
# which lib/lota.rb runs before require "lota/native"). Windows looks for a
# DLL an extension links by its name alone, in directories the process
# chooses, which under RubyInstaller are Ruby's own, those
# RubyInstaller::Runtime.add_dll_directory added, in an order Windows
# leaves unspecified, and System32 (SetDefaultDllDirectories with
# LOAD_LIBRARY_SEARCH_DEFAULT_DIRS), never the extension's directory. So a
# same-named DLL there, such as a player's MSYS2 or Creative's
# OpenAL32.dll in System32, could answer in place of the gem's. A DLL
# already loaded answers by its name first, so the preloader loads each of
# the engine's DLLs by its absolute path, from lib/lota/libraries, beside
# the preloader, before Ruby loads the extension.
add_library(lota_preload MODULE preload_windows.cpp)
lota_ruby_extension(lota_preload lota/preload ${LOTA_ROOT}/lib/lota)

# The DLLs it loads, by name, in the order the engine lists them, as wide
# string literals the preloader includes.
set(names "")
foreach(library IN LISTS ENGINE_RUNTIME_LIBRARIES)
	get_filename_component(name ${library} NAME)
	string(APPEND names "L\"${name}\",\n")
endforeach()
file(CONFIGURE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/libraries.inc CONTENT "${names}")
target_include_directories(lota_preload PRIVATE ${CMAKE_CURRENT_BINARY_DIR})

# The DLLs themselves, beside the preloader in the build tree's
# lib/lota/libraries, from which extconf.rb's Makefile copies them with it.
set(libraries ${CMAKE_BINARY_DIR}/lib/lota/libraries)
add_custom_command(TARGET lota_preload POST_BUILD
	COMMAND ${CMAKE_COMMAND} -E make_directory ${libraries}
	COMMAND ${CMAKE_COMMAND} -E copy_if_different ${ENGINE_RUNTIME_LIBRARIES} ${libraries}
	VERBATIM)
