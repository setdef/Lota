# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LÖVE's dependencies on Windows with MinGW (the spike for ADR 002,
# section 4): the shared libraries MSYS2's UCRT64 or CLANGARM64 packages
# install, found beside the compiler, which MSYS2 installs in the same
# prefix. Their import libraries are in lib/, their DLLs in bin/.

get_filename_component(compiler_dir ${CMAKE_CXX_COMPILER} DIRECTORY)
get_filename_component(default_prefix ${compiler_dir}/.. ABSOLUTE)
set(ENGINE_DEPS_DIR ${default_prefix} CACHE PATH "The MSYS2 prefix holding LÖVE's dependencies")
if(NOT EXISTS ${ENGINE_DEPS_DIR}/lib/libSDL3.dll.a)
	message(FATAL_ERROR "${ENGINE_DEPS_DIR} holds no lib/libSDL3.dll.a; install MSYS2's SDL3 package")
endif()
# Windows has no rpath; the DLLs are found at load time by the search
# order the process sets (RubyInstaller: RUBY_DLL_PATH, or
# RubyInstaller::Runtime.add_dll_directory).
set(ENGINE_LIBRARY_DIRS ${ENGINE_DEPS_DIR}/bin PARENT_SCOPE)

target_include_directories(lota_engine PUBLIC
	${ENGINE_DEPS_DIR}/include
	${ENGINE_DEPS_DIR}/include/AL
	${ENGINE_DEPS_DIR}/include/freetype2
	${ENGINE_DEPS_DIR}/include/harfbuzz
)

find_package(Threads REQUIRED)
target_link_libraries(lota_engine INTERFACE
	${ENGINE_DEPS_DIR}/lib/libSDL3.dll.a
	${ENGINE_DEPS_DIR}/lib/libfreetype.dll.a
	${ENGINE_DEPS_DIR}/lib/libharfbuzz.dll.a
	${ENGINE_DEPS_DIR}/lib/libopenal.dll.a
	${ENGINE_DEPS_DIR}/lib/libmodplug.dll.a
	${ENGINE_DEPS_DIR}/lib/libtheoradec.dll.a
	${ENGINE_DEPS_DIR}/lib/libvorbisfile.dll.a
	${ENGINE_DEPS_DIR}/lib/libvorbis.dll.a
	${ENGINE_DEPS_DIR}/lib/libogg.dll.a
	${ENGINE_DEPS_DIR}/lib/libz.dll.a
	# What LÖVE's own Windows build links liblove with
	# (vendor/love/CMakeLists.txt:1987-1992), and enet's winmm (line 1385).
	ws2_32
	winmm
	dwmapi
	Threads::Threads
)
