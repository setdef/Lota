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
else()
	message(FATAL_ERROR "Lota builds its engine on macOS and Linux only, not ${CMAKE_SYSTEM_NAME}.")
endif()

# Lota's physics patch (ADR 001, section 2, and physics.patch), applied to a
# copy of LÖVE's physics module in the build tree, which the engine compiles
# in place of vendor/love's. The copy is made when CMake configures, again
# whenever the patch or a file of the module changes, and a patched file is
# written only when it differs, so an unchanged file is not rebuilt.
set(PHYSICS_PATCH ${CMAKE_CURRENT_SOURCE_DIR}/physics.patch)
set(PATCHED_SOURCE_DIR ${CMAKE_BINARY_DIR}/patched/love)
set(PHYSICS_STAGING ${CMAKE_BINARY_DIR}/patched/staging)
file(GLOB_RECURSE PHYSICS_FILES RELATIVE ${ENGINE_SOURCE_DIR} ${ENGINE_SOURCE_DIR}/src/modules/physics/*)
list(FILTER PHYSICS_FILES EXCLUDE REGEX "/wrap_[^/]*$")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${PHYSICS_PATCH})
file(REMOVE_RECURSE ${PHYSICS_STAGING})
foreach(path IN LISTS PHYSICS_FILES)
	set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${ENGINE_SOURCE_DIR}/${path})
	configure_file(${ENGINE_SOURCE_DIR}/${path} ${PHYSICS_STAGING}/${path} COPYONLY)
endforeach()
execute_process(
	COMMAND patch -p1 --forward --batch --silent --no-backup-if-mismatch -i ${PHYSICS_PATCH}
	WORKING_DIRECTORY ${PHYSICS_STAGING}
	RESULT_VARIABLE physics_patch_result
	OUTPUT_VARIABLE physics_patch_output
	ERROR_VARIABLE physics_patch_output)
if(NOT physics_patch_result EQUAL 0)
	message(FATAL_ERROR "physics.patch does not apply to ${ENGINE_SOURCE_DIR}/src/modules/physics; "
		"update it for this LÖVE:\n${physics_patch_output}")
endif()
file(GLOB_RECURSE PATCHED_FILES RELATIVE ${PHYSICS_STAGING} ${PHYSICS_STAGING}/*)
foreach(path IN LISTS PATCHED_FILES)
	cmake_path(GET path PARENT_PATH directory)
	file(MAKE_DIRECTORY ${PATCHED_SOURCE_DIR}/${directory})
	file(COPY_FILE ${PHYSICS_STAGING}/${path} ${PATCHED_SOURCE_DIR}/${path} ONLY_IF_DIFFERENT)
endforeach()
set(patched_sources)
foreach(source IN LISTS ENGINE_SOURCES)
	string(REPLACE "${ENGINE_SOURCE_DIR}/src/modules/physics/" "${PATCHED_SOURCE_DIR}/src/modules/physics/"
		source "${source}")
	list(APPEND patched_sources ${source})
endforeach()
set(ENGINE_SOURCES ${patched_sources})

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

if(APPLE)
	include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies_macos.cmake)
else()
	include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies_linux.cmake)
endif()
