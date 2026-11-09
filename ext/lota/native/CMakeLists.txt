# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Lota::Native, the Ruby extension that binds LÖVE's engine (require
# "lota/native"). It is loaded from lib/lota, where `rake compile` and
# `gem install` put it, except in the sanitized tree, whose bundles
# rake test:native loads from where CMake writes them.
# The bindings tasks/bindings writes from LÖVE's wrap functions (rake
# bindings:generate), listed by the generator itself.
include(${CMAKE_CURRENT_SOURCE_DIR}/generated/sources.cmake)

add_library(lota_native ${LOTA_EXTENSION_TYPE}
	${LOTA_GENERATED_SOURCES}
	audio.cpp
	buffer.cpp
	data.cpp
	event.cpp
	filesystem.cpp
	font.cpp
	graphics.cpp
	image.cpp
	joystick.cpp
	keyboard.cpp
	math.cpp
	mouse.cpp
	native.cpp
	particle_system.cpp
	physics.cpp
	random_generator.cpp
	sensor.cpp
	shader.cpp
	signal.cpp
	sound.cpp
	system.cpp
	texture.cpp
	timer.cpp
	touch.cpp
	video.cpp
	window.cpp
)
if(LOTA_SANITIZE)
	set(load_directory ${CMAKE_BINARY_DIR}/lib/lota)
else()
	set(load_directory ${LOTA_ROOT}/lib/lota)
endif()
lota_ruby_extension(lota_native lota/native ${load_directory})
