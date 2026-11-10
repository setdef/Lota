# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Ruby and Rice, and lota_ruby_extension() for the targets that use them.
#
# extconf.rb passes Ruby_EXECUTABLE (the Ruby running it) and RICE_DIR (the
# installed rice gem), so an extension builds against the Ruby that will
# load it and the Rice that lota.gemspec pins.

set(RICE_DIR "" CACHE PATH "The rice gem's directory (extconf.rb sets it)")
if(NOT EXISTS ${RICE_DIR}/include/rice/rice.hpp)
	message(FATAL_ERROR "RICE_DIR (${RICE_DIR}) holds no include/rice/rice.hpp; "
		"configure through ext/lota/extconf.rb (rake compile)")
endif()

if(CMAKE_SYSTEM_NAME MATCHES "^(iOS|Android)$")
	# The phone's Ruby cannot run here, so FindRuby cannot ask it where its
	# headers are; extconf.rb, which runs under that Ruby's rbconfig.rb,
	# passes them. The extension is a static archive the app links, with
	# Ruby itself (Fledge's FledgeRuby.xcframework), or on Android into the
	# app's libfledgeext.so, which links Fledge's libfledgeruby.so.
	set(LOTA_RUBY_INCLUDE_DIRS "" CACHE STRING "The phone's Ruby headers (extconf.rb sets them)")
	if(NOT LOTA_RUBY_INCLUDE_DIRS)
		message(FATAL_ERROR "LOTA_RUBY_INCLUDE_DIRS is empty; configure through ext/lota/extconf.rb")
	endif()
	add_library(Ruby::Module INTERFACE IMPORTED)
	set_target_properties(Ruby::Module PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${LOTA_RUBY_INCLUDE_DIRS}")
	set(LOTA_EXTENSION_TYPE STATIC)
else()
	# Rice's FindRuby.cmake defines Ruby::Module, which CMake's own FindRuby
	# gains only in CMake 4.3 (docs/packaging/cmake.md, "FindRuby").
	list(PREPEND CMAKE_MODULE_PATH ${RICE_DIR})
	# FindRuby asks a Ruby_EXECUTABLE it has not seen for its paths, but
	# keeps the headers and library find_path and find_library cached, so
	# a build directory configured for one Ruby went on compiling against
	# its headers under another. They are found again on every configure.
	unset(Ruby_INCLUDE_DIR CACHE)
	unset(Ruby_CONFIG_INCLUDE_DIR CACHE)
	unset(Ruby_LIBRARY CACHE)
	find_package(Ruby 4.0 REQUIRED COMPONENTS Development)
	set(LOTA_EXTENSION_TYPE MODULE)
	# A development Ruby, such as a preview, defines RUBY_ABI_VERSION in its
	# config.h, and then refuses to load an extension that does not export
	# ruby_abi_version, which ruby/internal/abi.h defines in every file that
	# includes ruby.h (dln.c, dln_load_and_init). A released Ruby defines
	# neither, so the bundle exports it only for a development Ruby.
	file(STRINGS ${Ruby_CONFIG_INCLUDE_DIR}/ruby/config.h LOTA_RUBY_ABI_VERSION REGEX "^#define RUBY_ABI_VERSION ")
endif()

# lota_ruby_extension(<target> <feature> <load directory>)
#
# Makes <target> a Ruby extension that `require "<feature>"` loads: a bundle
# named after the feature's last part, written to lib/<feature's directory>
# in the build tree, that exports Init_<name> and nothing else.
#
# <load directory> is where the bundle is loaded from. The rpaths to LÖVE's
# frameworks, or on Linux its shared libraries, are relative to it
# (@loader_path, or $ORIGIN), never absolute, so nothing in the bundle
# names a path on the machine that built it.
function(lota_ruby_extension target feature load_directory)
	get_filename_component(name ${feature} NAME)
	get_filename_component(directory ${feature} DIRECTORY)
	if(LOTA_EXTENSION_TYPE STREQUAL "MODULE")
		get_target_property(suffix Ruby::Module INTERFACE_RUBY_EXTENSION_SUFFIX)
		set_target_properties(${target} PROPERTIES PREFIX "" OUTPUT_NAME ${name} SUFFIX ${suffix})
	endif()

	set_target_properties(${target} PROPERTIES
		LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib/${directory}
		ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib/${directory}
		# C++20 for the constrained partial specializations of
		# Rice::detail::Wrapper in native/binding.hpp.
		CXX_STANDARD 20
		CXX_STANDARD_REQUIRED ON
		CXX_EXTENSIONS OFF
		CXX_VISIBILITY_PRESET hidden
		VISIBILITY_INLINES_HIDDEN ON)

	# Rice's single header warns under -Wall -Wextra, so it is a system
	# header, like LÖVE's (engine/CMakeLists.txt) and Ruby's (an imported
	# target's include directories are system directories).
	target_include_directories(${target} SYSTEM PRIVATE ${RICE_DIR}/include)
	# Rice 4.12's rice.hpp is one file joined from many, and uses parts of
	# the standard library (std::exception_ptr at line 1124, std::transform
	# at 9962) before the line that includes their header. libstdc++ and
	# Apple's libc++ reach them through headers included earlier, but
	# MSYS2's CLANGARM64 libc++ does not, so there every standard header
	# Rice includes is included first, changing no file of Rice's.
	if(MINGW AND CMAKE_CXX_COMPILER_ID MATCHES "Clang")
		foreach(header IN ITEMS algorithm any array cmath complex cstdio cstdlib cstring exception filesystem
				fstream functional ios iosfwd iostream iterator limits map memory optional ostream regex set
				sstream stdexcept string string_view tuple type_traits typeindex typeinfo unordered_map utility
				variant vector)
			target_compile_options(${target} PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-include${header}>)
		endforeach()
	endif()
	target_include_directories(${target} PRIVATE ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/..)
	# Ruby's import library exports Sleep, its rb_w32_Sleep (win32/win32.c),
	# which needs a thread of Ruby's. MinGW's DLL startup, dllcrt2.o, which
	# comes first in every link, imports Sleep, and the linker takes it from
	# the first library that has it, so with Ruby's first every Sleep in
	# the extension is Ruby's, winpthreads' among them, which a thread calls
	# as it starts and crashes there. Windows' own kernel32 goes first.
	if(MINGW)
		target_link_libraries(${target} PRIVATE kernel32)
	endif()
	target_link_libraries(${target} PRIVATE Ruby::Module lota_engine)
	lota_strict_warnings(${target})

	# The linker's map of the bundle: every object file it took, from the
	# engine's archive among them. The precompiled gem reads it to learn
	# which libraries the bundle carries, and so which licenses it must
	# record (tasks/native_gem.rb).
	set(map ${CMAKE_BINARY_DIR}/lib/${directory}/${name}.map)
	if(LOTA_EXTENSION_TYPE STREQUAL "STATIC")
		# A static extension is linked into the app with every other one,
		# so Init_<name> becomes lota_Init_<name>, and the Init_<name> that
		# Fledge renames and registers is the one in phone/ that mkmf
		# compiles, which calls it (extconf.rb).
		target_compile_definitions(${target} PRIVATE Init_${name}=lota_Init_${name})
	elseif(APPLE)
		lota_link_macos(${target} ${name} ${map} ${load_directory})
	elseif(MINGW)
		lota_link_mingw(${target} ${name} ${map})
	else()
		lota_link_linux(${target} ${name} ${map} ${load_directory})
	endif()
endfunction()

# Apple's linker, for a bundle loaded from <load directory>.
function(lota_link_macos target name map load_directory)
	# Hidden visibility covers Lota's code and Rice's, but the engine's
	# archive was compiled with default visibility, so the linker is told
	# what to export. Each bundle then keeps its own copy of Rice's
	# registries and LÖVE's statics instead of dyld coalescing them with
	# another bundle's.
	target_link_options(${target} PRIVATE "LINKER:-exported_symbol,_Init_${name}")
	if(LOTA_RUBY_ABI_VERSION)
		target_link_options(${target} PRIVATE "LINKER:-exported_symbol,_ruby_abi_version")
	endif()
	# Record only the frameworks the bundle uses: the engine's interface
	# links every framework LÖVE needs, and a bundle that binds no window
	# needs none of them at load time.
	target_link_options(${target} PRIVATE "LINKER:-dead_strip_dylibs")
	target_link_options(${target} PRIVATE "LINKER:-map,${map}")

	foreach(frameworks IN LISTS ENGINE_LIBRARY_DIRS)
		file(RELATIVE_PATH relative ${load_directory} ${frameworks})
		target_link_options(${target} PRIVATE "LINKER:-rpath,@loader_path/${relative}")
	endforeach()
endfunction()

# GNU ld, for a shared object loaded from <load directory>: the same three
# things Apple's linker is told, in its terms.
function(lota_link_linux target name map load_directory)
	# Export Init_<name> alone, as -exported_symbol does: a version script
	# makes every other symbol local, the engine archive's among them, so
	# each extension keeps its own copy of Rice's registries and LÖVE's
	# statics instead of the dynamic linker binding them to another's.
	set(script ${CMAKE_CURRENT_BINARY_DIR}/${name}.version)
	set(exported "Init_${name};")
	if(LOTA_RUBY_ABI_VERSION)
		string(APPEND exported " ruby_abi_version;")
	endif()
	file(WRITE ${script} "{ global: ${exported} local: *; };\n")
	target_link_options(${target} PRIVATE "LINKER:--version-script=${script}")
	set_property(TARGET ${target} APPEND PROPERTY LINK_DEPENDS ${script})
	# Record only the libraries the extension uses, as -dead_strip_dylibs.
	target_link_options(${target} PRIVATE "LINKER:--as-needed")
	target_link_options(${target} PRIVATE "LINKER:-Map=${map}")

	# Only rpaths relative to the extension ($ORIGIN), never the absolute
	# ones CMake adds for each library it links by path, so nothing in it
	# names a path on the machine that built it.
	set(rpaths)
	foreach(libraries IN LISTS ENGINE_LIBRARY_DIRS)
		file(RELATIVE_PATH relative ${load_directory} ${libraries})
		list(APPEND rpaths "\$ORIGIN/${relative}")
	endforeach()
	set_target_properties(${target} PROPERTIES BUILD_WITH_INSTALL_RPATH ON INSTALL_RPATH "${rpaths}")
endfunction()

# MinGW's linker (GNU ld with GCC, LLD with clang), for a DLL Ruby loads
# (ADR 011). Windows has no rpath: the DLLs the extension links
# are loaded before it, by their absolute paths (preload/).
function(lota_link_mingw target name map)
	# Export Init_<name> alone. A module definition file is an explicit
	# export, which turns off ld's default of exporting every symbol (the
	# engine's archive would overflow the 65535 ordinals a DLL can export).
	set(definitions ${CMAKE_CURRENT_BINARY_DIR}/${name}.def)
	file(WRITE ${definitions} "EXPORTS\n\tInit_${name}\n")
	target_sources(${target} PRIVATE ${definitions})
	# GNU ld's map names each archive member it took with the archive's
	# path. LLD's -Map, its /lldmap, names a member by its own name alone,
	# so with clang the map is the one link.exe's /map writes, whose
	# Lib:Object column gives the archive's name beside the member's
	# (lld/COFF/MapFile.cpp), passed through LLD's MinGW driver as -Xlink.
	if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
		target_link_options(${target} PRIVATE "LINKER:-Xlink=-map:${map}")
	else()
		target_link_options(${target} PRIVATE "LINKER:-Map=${map}")
	endif()
	# The compiler's runtime inside the extension, so it needs no
	# libgcc_s, libstdc++, libc++, libunwind, or libwinpthread DLL, and
	# never binds to another copy that a different gem, or MSYS2, put in
	# the process. -static-libstdc++ alone leaves winpthreads, which GCC's
	# libstdc++ uses, to the -lpthread GCC's driver adds after everything
	# else, as a DLL; -static has the driver link every library it adds
	# from its archive. Ruby, OpenAL Soft, and Windows are linked by their
	# import libraries, which are archives too, so they stay DLLs.
	target_link_options(${target} PRIVATE -static)
endfunction()
