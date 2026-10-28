# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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

# Rice's FindRuby.cmake defines Ruby::Module, which CMake's own FindRuby
# gains only in CMake 4.3 (docs/packaging/cmake.md, "FindRuby").
list(PREPEND CMAKE_MODULE_PATH ${RICE_DIR})
find_package(Ruby 4.0 REQUIRED COMPONENTS Development)

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
	get_target_property(suffix Ruby::Module INTERFACE_RUBY_EXTENSION_SUFFIX)

	set_target_properties(${target} PROPERTIES
		PREFIX ""
		OUTPUT_NAME ${name}
		SUFFIX ${suffix}
		LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib/${directory}
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
	target_include_directories(${target} PRIVATE ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/..)
	target_link_libraries(${target} PRIVATE Ruby::Module lota_engine)
	lota_strict_warnings(${target})

	# The linker's map of the bundle: every object file it took, from the
	# engine's archive among them. The precompiled gem reads it to learn
	# which libraries the bundle carries, and so which licenses it must
	# record (tasks/native_gem.rb).
	set(map ${CMAKE_BINARY_DIR}/lib/${directory}/${name}.map)
	if(APPLE)
		lota_link_macos(${target} ${name} ${map} ${load_directory})
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
	file(WRITE ${script} "{ global: Init_${name}; local: *; };\n")
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
