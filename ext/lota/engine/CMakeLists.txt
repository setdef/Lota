# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LÖVE's engine as one static library, without its Lua layer (ADR 001,
# section 1). LÖVE's own CMakeLists.txt cannot build it: each module target
# lists its wrap_*.cpp files, so none links without Lua. The sources come
# from a list `rake engine:sources` generates from LÖVE's CMakeLists.txt.

# rake engine:sources generates each platform's list on that platform.
if(APPLE)
	include(${CMAKE_CURRENT_SOURCE_DIR}/sources_macos.cmake)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
	include(${CMAKE_CURRENT_SOURCE_DIR}/sources_linux.cmake)
elseif(MINGW)
	# Windows, with MinGW (ADR 002, section 4).
	include(${CMAKE_CURRENT_SOURCE_DIR}/sources_windows.cmake)
else()
	message(FATAL_ERROR "Lota builds its engine on macOS, Linux, and MinGW only, not ${CMAKE_SYSTEM_NAME}.")
endif()

# Lota's patches of LÖVE's engine, each applied to a copy of the files it
# changes in the build tree, which the engine compiles in place of
# vendor/love's: physics.patch (ADR 001, section 2) to LÖVE's physics
# module, and mesh.patch, which frees a Mesh's vertex data as it was
# allocated, to graphics/Mesh.cpp. The copy is made when CMake configures,
# again whenever a patch or one of the files it patches is edited, and a
# patched file is written only when it differs, so an unchanged file is not
# rebuilt.
set(PHYSICS_PATCH ${CMAKE_CURRENT_SOURCE_DIR}/physics.patch)
set(MESH_PATCH ${CMAKE_CURRENT_SOURCE_DIR}/mesh.patch)
set(MESH_SOURCE src/modules/graphics/Mesh.cpp)
set(PATCHED_SOURCE_DIR ${CMAKE_BINARY_DIR}/patched/love)
set(PATCH_STAGING ${CMAKE_BINARY_DIR}/patched/staging)
file(GLOB_RECURSE PHYSICS_FILES RELATIVE ${ENGINE_SOURCE_DIR} ${ENGINE_SOURCE_DIR}/src/modules/physics/*)
list(FILTER PHYSICS_FILES EXCLUDE REGEX "/wrap_[^/]*$")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${PHYSICS_PATCH} ${MESH_PATCH})
file(REMOVE_RECURSE ${PATCH_STAGING})
foreach(path IN LISTS PHYSICS_FILES MESH_SOURCE)
	set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${ENGINE_SOURCE_DIR}/${path})
	configure_file(${ENGINE_SOURCE_DIR}/${path} ${PATCH_STAGING}/${path} COPYONLY)
endforeach()
foreach(patch IN ITEMS physics mesh)
	string(TOUPPER ${patch} name)
	execute_process(
		COMMAND patch -p1 --forward --batch --silent --no-backup-if-mismatch -i ${${name}_PATCH}
		WORKING_DIRECTORY ${PATCH_STAGING}
		RESULT_VARIABLE patch_result
		OUTPUT_VARIABLE patch_output
		ERROR_VARIABLE patch_output)
	if(NOT patch_result EQUAL 0)
		message(FATAL_ERROR "${patch}.patch does not apply to ${ENGINE_SOURCE_DIR}; "
			"update it for this LÖVE:\n${patch_output}")
	endif()
endforeach()
file(GLOB_RECURSE PATCHED_FILES RELATIVE ${PATCH_STAGING} ${PATCH_STAGING}/*)
foreach(path IN LISTS PATCHED_FILES)
	cmake_path(GET path PARENT_PATH directory)
	file(MAKE_DIRECTORY ${PATCHED_SOURCE_DIR}/${directory})
	file(COPY_FILE ${PATCH_STAGING}/${path} ${PATCHED_SOURCE_DIR}/${path} ONLY_IF_DIFFERENT)
endforeach()
set(patched_sources)
foreach(source IN LISTS ENGINE_SOURCES)
	string(REPLACE "${ENGINE_SOURCE_DIR}/src/modules/physics/" "${PATCHED_SOURCE_DIR}/src/modules/physics/"
		source "${source}")
	if(source STREQUAL "${ENGINE_SOURCE_DIR}/${MESH_SOURCE}")
		set(source ${PATCHED_SOURCE_DIR}/${MESH_SOURCE})
	endif()
	list(APPEND patched_sources ${source})
endforeach()
set(ENGINE_SOURCES ${patched_sources})
# The patched Mesh.cpp's copy sits without the headers beside it, which it
# includes in quotes ("Mesh.h", "Shader.h", "Graphics.h"); -iquote searches
# its original folder next, where the compiler found them before.
set_source_files_properties(${PATCHED_SOURCE_DIR}/${MESH_SOURCE} PROPERTIES
	COMPILE_OPTIONS "-iquote;${ENGINE_SOURCE_DIR}/src/modules/graphics")

add_library(lota_engine STATIC ${ENGINE_SOURCES})

# A game that is not fused saves in a Lota folder where LÖVE's saves in a
# LOVE one (appdata_folder.h says how, and why not by a definition here).
set_source_files_properties(${ENGINE_SOURCE_DIR}/src/modules/filesystem/physfs/Filesystem.cpp PROPERTIES
	COMPILE_OPTIONS "-include;${CMAKE_CURRENT_SOURCE_DIR}/appdata_folder.h")

# Consumers see LÖVE's headers as system headers, so Lota's -Werror never
# fires on a warning in LÖVE's code.
set_target_properties(lota_engine PROPERTIES SYSTEM ON)

target_include_directories(lota_engine PUBLIC
	# The patched physics module, before LÖVE's own modules, so that
	# "physics/box2d/World.h" is the patched header everywhere.
	${PATCHED_SOURCE_DIR}/src/modules
	# The Xcode project's HEADER_SEARCH_PATHS
	# (platform/xcode/love.xcodeproj/project.pbxproj:576-580), and LÖVE's
	# CMakeLists.txt's include_directories (vendor/love/CMakeLists.txt:1895-1901).
	${ENGINE_SOURCE_DIR}/src
	${ENGINE_SOURCE_DIR}/src/libraries
	${ENGINE_SOURCE_DIR}/src/modules
	# vendor/love/CMakeLists.txt:1384, for <enet/enet.h>.
	${ENGINE_SOURCE_DIR}/src/libraries/enet/libenet/include
)

target_compile_definitions(lota_engine PUBLIC
	# "required for enet" (vendor/love/CMakeLists.txt:175-176).
	HAS_SOCKLEN_T
)

target_compile_options(lota_engine PRIVATE
	# LÖVE's warnings are LÖVE's to fix, upstream (ADR 001, section 1).
	-w
)
# data/Compressor.cpp:91 and filesystem/NativeFile.cpp:341
# use std::nothrow without including <new>, which libstdc++ and Apple's
# libc++ include through other headers, but MSYS2's CLANGARM64 libc++
# does not. Forcing the header in changes no file of LÖVE's.
if(MINGW AND CMAKE_CXX_COMPILER_ID MATCHES "Clang")
	target_compile_options(lota_engine PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-includenew>)
endif()

if(APPLE)
	include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies_macos.cmake)
elseif(MINGW)
	include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies_windows.cmake)
else()
	include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies_linux.cmake)
endif()
