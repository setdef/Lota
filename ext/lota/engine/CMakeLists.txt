# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# LÖVE's engine as one static library, without its Lua layer (ADR 001,
# section 1). LÖVE's own CMakeLists.txt cannot build it: each module target
# lists its wrap_*.cpp files, so none links without Lua. The sources come
# from a list `rake engine:sources` generates from LÖVE's CMakeLists.txt.

# rake engine:sources generates each platform's list on that platform, and
# iOS's on macOS, which has Xcode's iOS SDKs.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
	include(${CMAKE_CURRENT_SOURCE_DIR}/sources_ios.cmake)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Android")
	# rake android:sources evaluates it where the NDK is.
	include(${CMAKE_CURRENT_SOURCE_DIR}/sources_android.cmake)
elseif(APPLE)
	include(${CMAKE_CURRENT_SOURCE_DIR}/sources_macos.cmake)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
	include(${CMAKE_CURRENT_SOURCE_DIR}/sources_linux.cmake)
elseif(MINGW)
	# Windows, with MinGW (ADR 002, section 4).
	include(${CMAKE_CURRENT_SOURCE_DIR}/sources_windows.cmake)
else()
	message(FATAL_ERROR "Lota builds its engine for macOS, iOS, Android, Linux, and MinGW only, not ${CMAKE_SYSTEM_NAME}.")
endif()

# Lota's patches of LÖVE's engine, each applied to a copy of the files it
# changes in the build tree, which the engine compiles in place of
# vendor/love's: physics.patch (ADR 001, section 2) to LÖVE's physics
# module, and mesh.patch, which frees a Mesh's vertex data as it was
# allocated, to graphics/Mesh.cpp, lz4.patch, which backports LZ4's own
# fix for its arithmetic on null pointers, to libraries/lz4/lz4.c, and for
# Android alone vulkan_present.patch, which keeps a suboptimal present
# from rebuilding the swap chain, to graphics/vulkan/Graphics.cpp; every
# other platform compiles LÖVE's own file. The copy is made when CMake configures,
# again whenever a patch or one of the files it patches is edited, and a
# patched file is written only when it differs, so an unchanged file is not
# rebuilt.
set(PHYSICS_PATCH ${CMAKE_CURRENT_SOURCE_DIR}/physics.patch)
set(MESH_PATCH ${CMAKE_CURRENT_SOURCE_DIR}/mesh.patch)
set(MESH_SOURCE src/modules/graphics/Mesh.cpp)
set(LZ4_PATCH ${CMAKE_CURRENT_SOURCE_DIR}/lz4.patch)
set(LZ4_SOURCE src/libraries/lz4/lz4.c)
set(VULKAN_PRESENT_PATCH ${CMAKE_CURRENT_SOURCE_DIR}/vulkan_present.patch)
set(VULKAN_PRESENT_SOURCE src/modules/graphics/vulkan/Graphics.cpp)
set(PATCHES physics mesh lz4)
set(PATCHED_FILES_ALONE MESH_SOURCE LZ4_SOURCE)
if(CMAKE_SYSTEM_NAME STREQUAL "Android")
	list(APPEND PATCHES vulkan_present)
	list(APPEND PATCHED_FILES_ALONE VULKAN_PRESENT_SOURCE)
endif()
set(PATCHED_SOURCE_DIR ${CMAKE_BINARY_DIR}/patched/love)
set(PATCH_STAGING ${CMAKE_BINARY_DIR}/patched/staging)
file(GLOB_RECURSE PHYSICS_FILES RELATIVE ${ENGINE_SOURCE_DIR} ${ENGINE_SOURCE_DIR}/src/modules/physics/*)
list(FILTER PHYSICS_FILES EXCLUDE REGEX "/wrap_[^/]*$")
file(REMOVE_RECURSE ${PATCH_STAGING})
set(PATCHED_PATHS ${PHYSICS_FILES})
foreach(patch IN LISTS PATCHES)
	string(TOUPPER ${patch} name)
	set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${${name}_PATCH})
endforeach()
foreach(file IN LISTS PATCHED_FILES_ALONE)
	list(APPEND PATCHED_PATHS ${${file}})
endforeach()
foreach(path IN LISTS PATCHED_PATHS)
	set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${ENGINE_SOURCE_DIR}/${path})
	configure_file(${ENGINE_SOURCE_DIR}/${path} ${PATCH_STAGING}/${path} COPYONLY)
endforeach()
foreach(patch IN LISTS PATCHES)
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
	foreach(file IN LISTS PATCHED_FILES_ALONE)
		if(source STREQUAL "${ENGINE_SOURCE_DIR}/${${file}}")
			set(source ${PATCHED_SOURCE_DIR}/${${file}})
		endif()
	endforeach()
	list(APPEND patched_sources ${source})
endforeach()
set(ENGINE_SOURCES ${patched_sources})
# The patched Mesh.cpp's copy sits without the headers beside it, which it
# includes in quotes ("Mesh.h", "Shader.h", "Graphics.h"); -iquote searches
# its original folder next, where the compiler found them before.
set_source_files_properties(${PATCHED_SOURCE_DIR}/${MESH_SOURCE} PROPERTIES
	COMPILE_OPTIONS "-iquote;${ENGINE_SOURCE_DIR}/src/modules/graphics")
# The patched lz4.c's likewise ("lz4.h").
set_source_files_properties(${PATCHED_SOURCE_DIR}/${LZ4_SOURCE} PROPERTIES
	COMPILE_OPTIONS "-iquote;${ENGINE_SOURCE_DIR}/src/libraries/lz4")
# The patched vulkan/Graphics.cpp's likewise ("Graphics.h", "Vulkan.h").
if(CMAKE_SYSTEM_NAME STREQUAL "Android")
	set_source_files_properties(${PATCHED_SOURCE_DIR}/${VULKAN_PRESENT_SOURCE} PROPERTIES
		COMPILE_OPTIONS "-iquote;${ENGINE_SOURCE_DIR}/src/modules/graphics/vulkan")
endif()

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

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
	include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies_ios.cmake)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Android")
	include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies_android.cmake)
elseif(APPLE)
	include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies_macos.cmake)
elseif(MINGW)
	include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies_windows.cmake)
else()
	include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies_linux.cmake)
endif()
