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

# love.audio
generate "love.audio.getActiveSourceCount"
bound_by_hand "love.audio.newSource",
  reason: "converts a filename into a Decoder, and a Decoder into SoundData, through love.sound's wrap " \
    "functions (luax_convobj); Lota binds the forms with a filename and a source type"
bound_by_hand "love.audio.play",
  reason: "reads a list of Sources from a table or from every argument (readSourceList, readSourceVararg), " \
    "which the parser does not read; Lota binds the form with one Source"
bound_by_hand "love.audio.stop",
  reason: "reads a list of Sources from a table or from every argument, as love.audio.play; Lota binds the " \
    "forms with no Source and with one"
generate "love.audio.setVolume"
generate "love.audio.getVolume"
generate "Source:play"
generate "Source:stop"
generate "Source:pause"
generate "Source:setPitch"
generate "Source:getPitch"
generate "Source:setVolume"
generate "Source:getVolume"
generate "Source:setLooping"
generate "Source:isLooping"
generate "Source:isPlaying"
generate "Source:getChannelCount"

# love.event
generate "love.event.pump"
generate "love.event.clear"
bound_by_hand "love.event.push",
  reason: "reads a Variant of any kind at every position after the name (luax_checkvariant), which Lota " \
    "narrows to the booleans, numbers, and strings an event carries"
bound_by_hand "love.event.quit",
  reason: "reads a Variant of any kind at every position (luax_checkvariant), which Lota narrows to an exit status"

# love.filesystem
generate "love.filesystem.init"
generate "love.filesystem.setSource"
bound_by_hand "love.filesystem.newFileData",
  reason: "converts its argument through luax_getfiledata; Lota ports Filesystem::newFileData so it need not " \
    "open PhysicsFS"

generate "love.filesystem.setFused"
generate "love.filesystem.isFused"
generate "love.filesystem.setIdentity"
generate "love.filesystem.getIdentity"
generate "love.filesystem.getSaveDirectory"
generate "love.filesystem.createDirectory"
generate "love.filesystem.remove"
bound_by_hand "love.filesystem.getInfo",
  reason: "reads its file type at a position it computes (startidx), and fills in a table it is given or makes, " \
    "which the generator does not port; Lota returns the fields, which Lota::Filesystem.info makes a frozen Data"
bound_by_hand "love.filesystem.read",
  reason: "reads its arguments at positions it computes (startidx), and catches the engine's exception with " \
    "try, which the parser does not read; Lota binds the form that reads into a string"
bound_by_hand "love.filesystem.write",
  reason: "returns w_write_or_append, a helper the parser does not follow, which reads a string or any Data " \
    "(luax_istype) and catches the engine's exception with try; Lota binds the two forms as two functions"
bound_by_hand "love.filesystem.lines",
  reason: "returns an iterator, a C closure over the open File (w_File_lines_i), which the generator does " \
    "not port; Lota binds the iterator as a class whose next_line Lota::Filesystem.lines enumerates"

# love.graphics
generate "love.graphics.isActive"
generate "love.graphics.isCreated"
generate "love.graphics.reset"
generate "love.graphics.origin"
bound_by_hand "love.graphics.push",
  reason: "tests its stack type's const char * as a bool (if (sname && ...)), which clang-tidy's " \
    "readability-implicit-bool-conversion refuses; Lota binds the form with a stack type alone, and the form " \
    "that applies a Transform waits for Transform"
generate "love.graphics.pop"
generate "love.graphics.translate"
generate "love.graphics.scale"
generate "love.graphics.shear"
generate "love.graphics.getBackgroundColor"
generate "love.graphics.getWidth"
generate "love.graphics.getHeight"
generate "love.graphics.getColor"
generate "love.graphics.setLineWidth"
generate "love.graphics.getLineWidth"
generate "love.graphics.setLineStyle"
generate "love.graphics.getLineStyle"
generate "love.graphics.rectangle"
generate "love.graphics.ellipse"
generate "love.graphics.circle"
generate "Texture:isCanvas"
generate "love.graphics.setFont"
generate "love.graphics.setDefaultFilter"
generate "SpriteBatch:clear"
generate "SpriteBatch:flush"
generate "SpriteBatch:setTexture"
bound_by_hand "SpriteBatch:setColor",
  reason: "LÖVE assigns each component in a statement of its own, so the port's four numbers fail clang-tidy's " \
    "bugprone-easily-swappable-parameters, as love.graphics.setColor's do; Lota binds the form with separate " \
    "numbers in one constructor call"
generate "SpriteBatch:getColor"
generate "SpriteBatch:getCount"
generate "SpriteBatch:getBufferSize"
generate "SpriteBatch:setDrawRange"
bound_by_hand "Quad:setViewport",
  reason: "LÖVE assigns each side of the viewport in a statement of its own, so the port's four numbers fail " \
    "clang-tidy's bugprone-easily-swappable-parameters; Lota binds the viewport as an Array, as draw's placement"
generate "Quad:getViewport"
generate "Quad:getTextureDimensions"
generate "Quad:setLayer"
bound_by_hand "Quad:getLayer",
  reason: "pushes quad->getLayer() + 1, whose C++ type the headers the generator reads do not give"
bound_by_hand "love.graphics.newQuad",
  reason: "chooses among its forms by its arguments' kinds, reading argument 5 as a Texture, a layer, or a " \
    "width; Lota::Graphics::Quad.new chooses as it does, and binds the forms with a texture and with numbers"
bound_by_hand "love.graphics.newSpriteBatch",
  reason: "pushes its SpriteBatch with luax_pushtype, which the generator does not port"
bound_by_hand "SpriteBatch:add",
  reason: "reads its placement through luax_checkstandardtransform, at a position that depends on whether a " \
    "Quad comes first; Lota binds the Quad or nil and the nine numbers as an Array, as draw"
bound_by_hand "SpriteBatch:set",
  reason: "reads its Quad and placement as SpriteBatch:add does"
bound_by_hand "SpriteBatch:getTexture",
  reason: "pushes its Texture with luax_pushtype, which the generator does not port"
generate "SpriteBatch:getDrawRange"
bound_by_hand "Texture:getWidth",
  reason: "reads its mipmap through w__optMipmap, which the generator does not port"
bound_by_hand "Texture:getHeight",
  reason: "reads its mipmap through w__optMipmap, as Texture:getWidth"
bound_by_hand "love.graphics.setColor",
  reason: "LÖVE assigns each component in a statement of its own, so the port's four numbers fail clang-tidy's " \
    "bugprone-easily-swappable-parameters; Lota binds the form with separate numbers in one constructor call"
bound_by_hand "love.graphics.present",
  reason: "passes LÖVE's lua_State to Graphics::present for its screenshot callbacks, which Lota replaces " \
    "with deliver_screenshot"
bound_by_hand "love.graphics.newCanvas",
  reason: "reads its settings table through luax_checktexturesettings, at a position it computes; Lota binds a " \
    "width, a height, and the msaa setting"
bound_by_hand "love.graphics.newImage",
  reason: "LÖVE 12 makes it with w_newTexture (wrap_Graphics.cpp:1251-1255); Lota::Graphics::Image.new calls " \
    "Lota::Graphics::Texture.new, bound with newTexture"
bound_by_hand "love.graphics.newTexture",
  reason: "chooses among its forms by its arguments' kinds, and reads its image through getImageData and " \
    "luax_getdata, which the generator does not port; Lota binds one image, from Data or an ImageData"
bound_by_hand "love.graphics.setCanvas",
  reason: "chooses among its forms by its arguments' kinds and count; Lota binds one texture (set_canvas) and " \
    "none (reset_canvas)"
bound_by_hand "love.graphics.clear",
  reason: "reads its stencil and depth at a position it computes (startidx)"
bound_by_hand "love.graphics.readbackTexture",
  reason: "reads its slice, mipmap, and rectangle at positions it computes; Lota binds the whole texture"
bound_by_hand "love.graphics.newFont",
  reason: "chooses among its forms by its arguments' kinds, and makes its Rasterizer through love.font's " \
    "wrap functions (w_newRasterizer, w_newTrueTypeRasterizer), which read a settings table; Lota binds the " \
    "default font at a size, a TrueType font in FileData at a size, and a font from FileData alone"
bound_by_hand "love.graphics.getFont",
  reason: "pushes its Font with luax_pushtype, which the generator does not port"
bound_by_hand "love.graphics.getDefaultFilter",
  reason: "pushes SamplerState's maxAnisotropy, whose C++ type the headers the generator reads do not give"
bound_by_hand "love.graphics.print",
  reason: "reads its text through luax_checkcoloredstring and its placement through " \
    "luax_checkstandardtransform, at positions that depend on whether a Font comes first; Lota binds the " \
    "form without a Font, with its text and nine numbers as Arrays"
bound_by_hand "love.graphics.printf",
  reason: "reads its text, Font, placement, and alignment at positions it computes; Lota binds the form " \
    "without a Font, as print"
bound_by_hand "love.graphics.draw",
  reason: "reads its placement at a position that depends on whether a Quad comes second; Lota binds a " \
    "Texture, a SpriteBatch, and a Texture through a Quad, each with its nine numbers as an Array, as print"
bound_by_hand "love.graphics.line",
  reason: "reads its coordinates in a loop over every argument, or from a table; Lota::Graphics.line passes " \
    "them as one Array"
bound_by_hand "love.graphics.arc",
  reason: "reads its position at an index that depends on whether an arc mode comes second; " \
    "Lota::Graphics.arc passes the arc mode or nil"
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

# love.mouse
bound_by_hand "love.mouse.getSystemCursor",
  reason: "pushes its Cursor with luax_pushtype, which the generator does not port"
generate "love.mouse.setCursor"
generate "love.mouse.getX"
generate "love.mouse.getY"
generate "love.mouse.getPosition"
generate "love.mouse.setX"
generate "love.mouse.setY"
generate "love.mouse.setPosition"
bound_by_hand "love.mouse.isDown",
  reason: "reads its buttons in a loop over every argument, or from a table; Lota::Mouse.down? passes them " \
    "as one Array, as Lota::Keyboard.down? passes its keys"
generate "love.mouse.setVisible"
generate "love.mouse.isVisible"
generate "love.mouse.setGrabbed"
generate "love.mouse.isGrabbed"
generate "love.mouse.setRelativeMode"
generate "love.mouse.getRelativeMode"
generate "love.mouse.isCursorSupported"

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
bound_by_hand "love.math._getRandomGenerator",
  reason: "pushes its RandomGenerator with luax_pushtype, which the generator does not port; Lota::Math draws " \
    "from it, as wrap_Math.lua does"
bound_by_hand "RandomGenerator:setSeed",
  reason: "reads its seed's two halves at a position it computes (luax_checkrandomseed); Lota binds the low " \
    "half and an optional high half"

# love.sound
bound_by_hand "love.sound.newDecoder",
  reason: "chooses among its forms by its argument's kind (luax_cangetfile, luax_istype) and pushes its " \
    "Decoder with luax_pushtype, which the generator does not port; Lota binds a filename with its stream type, " \
    "and Data"
bound_by_hand "love.sound.newSoundData",
  reason: "passes the lua_State to w_newDecoder, which the parser does not read, and pushes its SoundData with " \
    "luax_pushtype; Lota binds the form with numbers and the form with a Decoder, which " \
    "Lota::Sound::SoundData.new makes from a filename or a FileData first, as LÖVE does"
bound_by_hand "Decoder:decode",
  reason: "pushes its SoundData with luax_pushtype, or nil, which the generator does not port"
bound_by_hand "SoundData:slice",
  reason: "pushes its SoundData with luax_pushtype, which the generator does not port"
bound_by_hand "SoundData:getSample",
  reason: "LÖVE runs the LuaJIT version in wrap_SoundData.lua, which divides in double precision where the " \
    "C++ wrap function divides in a float; Lota ports the Lua, which the generator does not read"
bound_by_hand "SoundData:setSample",
  reason: "LÖVE runs the LuaJIT version in wrap_SoundData.lua, which multiplies in double precision and stores " \
    "through LuaJIT's conversions; Lota ports the Lua, which the generator does not read"
generate "SoundData:getChannelCount"
generate "SoundData:getBitDepth"
generate "SoundData:getSampleRate"
generate "SoundData:getSampleCount"
generate "SoundData:getDuration"
generate "SoundData:copyFrom"
generate "Data:getSize"
bound_by_hand "Data:getString",
  reason: "pushes its bytes with lua_pushlstring from a pointer it computes with a C-style cast and pointer " \
    "arithmetic, which clang-tidy refuses; Lota reads the same bytes through a std::span"
generate "Decoder:getChannelCount"
generate "Decoder:getBitDepth"
generate "Decoder:getSampleRate"
generate "Decoder:getDuration"

# love.system
generate "love.system.setClipboardText"
generate "love.system.getClipboardText"
generate "love.system.getOS"

# love.timer
generate "love.timer.step"
generate "love.timer.getDelta"
generate "love.timer.sleep"

# love.window
generate "love.window.getSafeArea"
bound_by_hand "love.window.getDesktopDimensions",
  reason: "declares its width and height in one statement with initializers (int width = 0, height = 0), " \
    "which the generator does not split, so it cannot type their pushes"
bound_by_hand "love.window.getMode",
  reason: "fills in a table it is given or makes with every setting (lua_setfield), which the generator does " \
    "not port; Lota fills a WindowSettings, which Lota::Window.mode makes a frozen Data"
bound_by_hand "love.window.updateMode",
  reason: "reads its settings at a position it computes (idx) through readWindowSettings, which the parser " \
    "does not read; Lota reads the window's settings into a WindowSettings, and Lota::Window.update_mode " \
    "reads its keywords into it as set_mode does"
generate "love.window.setTitle"
generate "love.window.getTitle"
generate "love.window.isOpen"
bound_by_hand "love.window.showMessageBox",
  reason: "chooses between its forms by whether its third argument is a table, which also holds the " \
    "enterbutton and escapebutton settings; Lota binds each form as a function of its own"
bound_by_hand "love.window.setMode",
  reason: "reads its settings table through readWindowSettings, which Lota::Window.set_mode ports to Ruby"
