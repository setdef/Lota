# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The LÖVE functions Lota::Native binds (tasks/bindings/binding_list.rb).
#
# `generate` lists a function the binding generator writes from its wrap
# function, into ext/lota/native/generated and
# sig/lota/native/generated.rbs (`rake bindings:generate`). A form it
# limits, by how many arguments it binds or by a condition that picks the
# form, says why. `bound_by_hand` lists a function bound in
# ext/lota/native/*.cpp instead, with the reason the generator cannot
# write it. LÖVE's boot-time functions in src/modules/love/love.cpp
# (_setGammaCorrect, _setRenderers, _setHighDPIAllowed, and the like) are
# not wrap functions, so they are bound by hand and not listed here.

# love.event
generate "love.event.pump"
bound_by_hand "love.event.quit",
  reason: "reads a Variant of any kind at every position (luax_checkvariant), which Lota narrows to an exit status"

# love.filesystem
bound_by_hand "love.filesystem.newFileData",
  reason: "converts its argument through luax_getfiledata; Lota ports Filesystem::newFileData so it need not " \
    "open PhysicsFS"

# love.graphics
generate "love.graphics.isActive"
generate "love.graphics.origin"
generate "love.graphics.getBackgroundColor"
generate "love.graphics.getWidth"
generate "love.graphics.getHeight"
generate "love.graphics.getColor"
generate "love.graphics.setLineWidth"
generate "love.graphics.getLineWidth"
generate "love.graphics.setLineStyle"
generate "love.graphics.getLineStyle"
generate "love.graphics.rectangle", arguments: 5,
  reason: "without rounded corners, as Lota::Graphics.rectangle binds it until a game needs them"
generate "love.graphics.circle"
generate "Texture:isCanvas"
bound_by_hand "love.graphics.setColor",
  reason: "LÖVE assigns each component in a statement of its own, so the port's four numbers fail clang-tidy's " \
    "bugprone-easily-swappable-parameters; Lota binds the form with separate numbers in one constructor call"
bound_by_hand "love.graphics.present",
  reason: "passes LÖVE's lua_State to Graphics::present for its screenshot callbacks, which Lota replaces " \
    "with deliver_screenshot"
bound_by_hand "love.graphics.newCanvas",
  reason: "reads its settings table through luax_checktexturesettings, at a position it computes"
bound_by_hand "love.graphics.setCanvas",
  reason: "chooses among its forms by its arguments' kinds and count; Lota binds one texture (set_canvas) and " \
    "none (reset_canvas)"
bound_by_hand "love.graphics.clear",
  reason: "reads its stencil and depth at a position it computes (startidx)"
bound_by_hand "love.graphics.readbackTexture",
  reason: "reads its slice, mipmap, and rectangle at positions it computes; Lota binds the whole texture"
bound_by_hand "love.graphics.captureScreenshot",
  reason: "takes a Lua function, a Channel, or a filename; Lota binds a Ruby callable for the parity harness"

# love.image
generate "ImageData:getWidth"
generate "ImageData:getHeight"
generate "ImageData:getPixel"
bound_by_hand "love.image.newImageData",
  reason: "chooses among its forms by its arguments' kinds; Lota binds the form that decodes Data"

# love.keyboard
bound_by_hand "love.keyboard.isDown",
  reason: "reads its keys in a loop over every argument, or from a table; Lota::Keyboard.down? passes them " \
    "as one Array"

# love.math
bound_by_hand "RandomGenerator:_random",
  reason: "clang-analyzer's security.insecureAPI.rand takes the port's call to a method named random for the C " \
    "library's random(), so Lota binds the method itself, as random"
generate "RandomGenerator:randomNormal", arguments: 1,
  reason: "the standard deviation alone, as Lota::Native has bound it since the walking skeleton; the mean " \
    "waits for Lota::Math"
generate "RandomGenerator:getState"
generate "RandomGenerator:setState"
bound_by_hand "love.math.newRandomGenerator",
  reason: "reads its seed's two halves at a position it computes; Lota binds the generator's constructor"

# love.timer
generate "love.timer.step"
generate "love.timer.sleep"

# love.window
generate "love.window.setTitle"
generate "love.window.getTitle"
bound_by_hand "love.window.setMode",
  reason: "reads its settings table through readWindowSettings, which Lota::Window.set_mode ports to Ruby"
