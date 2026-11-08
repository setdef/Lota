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
# write it. `bound_from_lua` lists a function whose C++ LÖVE replaces with
# Lua of its own, in a wrap_*.lua file, which Lota ports by hand, as a game
# runs the Lua (ADR 001, section 7); the generator knows which those are
# (tasks/bindings/lua_functions.rb), refuses to port their C++, and says
# where the Lua is and when it runs. LÖVE's boot-time functions in src/modules/love/love.cpp
# (_setGammaCorrect, _setRenderers, _setHighDPIAllowed, and the like) are
# not wrap functions, so they are bound by hand and not listed here.

# love.audio
generate "love.audio.getActiveSourceCount"
bound_by_hand "love.audio.newSource",
  reason: "converts a filename or Data into a Decoder, and a Decoder into SoundData, through love.sound's wrap " \
    "functions (luax_convobj); Lota::Audio::Source.new calls Lota::Sound's, and Lota binds the source type " \
    "check and the forms with a SoundData and a Decoder"
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
generate "Source:getType"
generate "Source:clone"
bound_by_hand "Source:seek",
  reason: "raises luaL_argerror for a negative offset, which the port does not write; Lota raises ArgumentError"
bound_by_hand "Source:tell",
  reason: "calls the static getConstant through its Source, which clang-tidy's " \
    "readability-static-accessed-through-instance refuses; Lota calls Source::getConstant"
bound_by_hand "Source:getDuration",
  reason: "calls the static getConstant through its Source, as Source:tell"
bound_by_hand "love.audio.setOrientation",
  reason: "reads six numbers into a C array, whose indices past four clang-tidy's readability-magic-numbers " \
    "refuses; Lota binds them as an Array"
bound_by_hand "love.audio.getOrientation",
  reason: "pushes six numbers from a C array, as love.audio.setOrientation reads them"
bound_by_hand "love.audio.getDistanceModel",
  reason: "returns no value where the model has no name, which no model LÖVE sets lacks; Lota binds the name"
generate "Source:setPosition"
generate "Source:getPosition"
generate "Source:setVelocity"
generate "Source:getVelocity"
generate "Source:setDirection"
generate "Source:getDirection"
generate "Source:setCone"
generate "Source:getCone"
generate "Source:setRelative"
generate "Source:isRelative"
generate "Source:setVolumeLimits"
generate "Source:getVolumeLimits"
generate "Source:setAttenuationDistances"
generate "Source:getAttenuationDistances"
generate "Source:setRolloff"
generate "Source:getRolloff"
generate "Source:setAirAbsorption"
generate "Source:getAirAbsorption"
generate "Source:getFreeBufferCount"
generate "love.audio.setPosition"
generate "love.audio.getPosition"
generate "love.audio.setVelocity"
generate "love.audio.getVelocity"
generate "love.audio.setDopplerScale"
generate "love.audio.getDopplerScale"
generate "love.audio.setDistanceModel"
generate "love.audio.newQueueableSource"
generate "love.audio.getMaxSceneEffects"
generate "love.audio.getMaxSourceEffects"
generate "love.audio.isEffectsSupported"
generate "love.audio.setMixWithSystem"
generate "love.audio.getPlaybackDevice"
generate "love.audio.setPlaybackDevice"
generate "love.audio.setOutputSpatialization"
generate "love.audio.getOutputSpatialization"
bound_by_hand "love.audio.getOutputSpatializationFilters",
  reason: "fills a table in a loop, which the generator does not port; Lota returns the names as an Array"
bound_by_hand "love.audio.getPlaybackDevices",
  reason: "fills a table in a loop, as love.audio.getOutputSpatializationFilters"
bound_by_hand "love.audio.getRecordingDevices",
  reason: "fills a table with the devices in a loop; Lota returns them as an Array"
bound_by_hand "love.audio.getActiveEffects",
  reason: "fills a table in a loop, as love.audio.getOutputSpatializationFilters"
bound_by_hand "love.audio.pause",
  reason: "returns the Sources it paused as a table it fills in a loop, and reads a list of Sources as " \
    "love.audio.play does; Lota binds the forms with no Source and with one"
bound_by_hand "love.audio.setEffect",
  reason: "reads its settings from a table with lua_next, each by the type its parameter has, which the " \
    "generator does not port; Lota reads them as the pairs Lota::Audio.set_effect makes of its keywords"
bound_by_hand "love.audio.getEffect",
  reason: "fills in a table it is given or makes, which the generator does not port; Lota returns the " \
    "settings as pairs, which Lota::Audio.effect makes a frozen record"
bound_by_hand "Source:setFilter",
  reason: "reads its settings through setFilterReadFilter, a helper the parser does not follow, as " \
    "love.audio.setEffect reads its own"
bound_by_hand "Source:getFilter",
  reason: "fills in a table through getFilterWriteFilter, as love.audio.getEffect fills its own"
bound_by_hand "Source:setEffect",
  reason: "reads a boolean or a filter's settings, by its Lua type, through setFilterReadFilter"
bound_by_hand "Source:getEffect",
  reason: "returns the filter's settings through getFilterWriteFilter after whether the effect is set"
bound_by_hand "Source:getActiveEffects",
  reason: "fills a table in a loop, as love.audio.getActiveEffects"
bound_by_hand "Source:queue",
  reason: "reads a SoundData or a light userdata, and its offset and length by how many arguments it is " \
    "given (lua_gettop); Lota binds the SoundData form, whose arguments Lota::Audio::Source#queue counts"
bound_by_hand "RecordingDevice:start",
  reason: "casts its channel count to int twice with C-style casts ((int) (int) luaL_optinteger), which " \
    "clang-tidy's modernize-avoid-c-style-cast refuses"
generate "RecordingDevice:stop"
generate "RecordingDevice:getData"
generate "RecordingDevice:getSampleCount"
generate "RecordingDevice:getSampleRate"
generate "RecordingDevice:getBitDepth"
generate "RecordingDevice:getChannelCount"
generate "RecordingDevice:getName"
generate "RecordingDevice:isRecording"

# love.data
bound_by_hand "love.data.newDataView",
  reason: "casts its offset and size to size_t with C-style casts, which clang-tidy's " \
    "modernize-avoid-c-style-cast refuses"
bound_by_hand "love.data.newByteData",
  reason: "chooses among its forms by its first argument's kind (luax_istype, lua_type), where Rice passes one " \
    "C++ type for each argument; Lota binds the forms with a Data, a string, and a size"
bound_by_hand "love.data.compress",
  reason: "reads its data as a string or a Data by its kind (lua_isstring), as love.data.newByteData chooses; " \
    "Lota binds both forms"
bound_by_hand "love.data.decompress",
  reason: "reads a CompressedData, or a format and a string or Data, by its argument's kind (luax_istype); " \
    "Lota binds each form"
bound_by_hand "love.data.encode",
  reason: "reads its source as a Data or a string by its kind (luax_istype), as love.data.decompress; Lota " \
    "binds both forms"
bound_by_hand "love.data.decode",
  reason: "reads its source as a Data or a string by its kind (luax_istype), as love.data.encode"
bound_by_hand "love.data.pack",
  reason: "packs its values through lua53_str_pack, Lua 5.3's string.pack, which reads them from the lua_State " \
    "and which Lota does not build (ADR 001, section 1); Lota::Data.pack ports it to Ruby and writes the bytes " \
    "through the engine"
bound_by_hand "love.data.unpack",
  reason: "unpacks through lua53_str_unpack, as love.data.pack packs; Lota::Data.unpack ports it to Ruby over " \
    "the Data's bytes"
bound_by_hand "love.data.getPackedSize",
  reason: "is lua53_str_packsize, Lua 5.3's string.packsize, outside the wrap files; Lota::Data.packed_size " \
    "ports it to Ruby"
generate "ByteData:clone"
bound_by_hand "ByteData:setString",
  reason: "reads its string's length into size with luaL_checklstring, which the port does not write, and " \
    "copies with memcpy to a pointer it computes with C-style casts, which clang-tidy refuses; Lota copies " \
    "through a std::span"
bound_by_hand "ByteData:setFloat",
  reason: "returns w_ByteData_setT<float>, a template the parser does not follow, which reads its values from " \
    "a table or from every argument in a loop; Lota binds them as an Array"
bound_by_hand "ByteData:setDouble",
  reason: "returns w_ByteData_setT<double>, as ByteData:setFloat"
bound_by_hand "ByteData:setInt8",
  reason: "returns w_ByteData_setT<int8>, as ByteData:setFloat"
bound_by_hand "ByteData:setUInt8",
  reason: "returns w_ByteData_setT<uint8>, as ByteData:setFloat"
bound_by_hand "ByteData:setInt16",
  reason: "returns w_ByteData_setT<int16>, as ByteData:setFloat"
bound_by_hand "ByteData:setUInt16",
  reason: "returns w_ByteData_setT<uint16>, as ByteData:setFloat"
bound_by_hand "ByteData:setInt32",
  reason: "returns w_ByteData_setT<int32>, as ByteData:setFloat"
bound_by_hand "ByteData:setUInt32",
  reason: "returns w_ByteData_setT<uint32>, as ByteData:setFloat"
generate "CompressedData:clone"
generate "CompressedData:getFormat"
generate "DataView:clone"

# love.event
generate "love.event.pump"
generate "love.event.clear"
bound_by_hand "love.event.push",
  reason: "reads a Variant of any kind at every position after the name (luax_checkvariant), which Lota " \
    "narrows to the booleans, numbers, and strings an event carries"
bound_by_hand "love.event.quit",
  reason: "reads a Variant of any kind at every position (luax_checkvariant), which Lota narrows to an exit status"
bound_by_hand "love.event.wait",
  reason: "returns a message's name and a computed number of arguments (luax_pushmessage), which the generator " \
    "does not port; Lota returns them as the Array Lota::Event.poll yields, as it does for the message w_poll_i " \
    "pushes"
bound_by_hand "love.event.restart",
  reason: "reads a Variant of any kind at every position, nil included (luax_checkvariant), which Lota reads " \
    "for the values Ruby has, a Proc as a function, and does not yet read as a table or a LÖVE object"
bound_by_hand "love.event.setModalDrawCallback",
  reason: "keeps a Lua function in a Reference and calls it with lua_cpcall (drawCallback), which the " \
    "generator does not port; Lota keeps a Ruby callable as a root of the garbage collector"
bound_by_hand "love.event._setDefaultModalDrawCallback",
  reason: "keeps a Lua function in a Reference, as love.event.setModalDrawCallback does; only Lota::Boot " \
    "calls it, with each new frame of its loop, as only boot.lua calls LÖVE's"

# love.filesystem
generate "love.filesystem.init"
generate "love.filesystem.setSource"
generate "FileData:clone"
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
  reason: "reads its arguments at positions it computes (startidx); Lota binds the form that reads into a " \
    "string"
bound_by_hand "love.filesystem.write",
  reason: "returns w_write_or_append, a helper the parser does not follow, which reads a string or any Data " \
    "(luax_istype); Lota binds the two forms as two functions"
bound_by_hand "love.filesystem.lines",
  reason: "returns an iterator, a C closure over the open File (w_File_lines_i), which the generator does " \
    "not port; Lota binds the iterator as a class whose next_line Lota::Filesystem.lines enumerates"
generate "love.filesystem.getSource"
generate "love.filesystem.mountFullPath"
generate "love.filesystem.mountCommonPath"
generate "love.filesystem.unmountFullPath"
generate "love.filesystem.unmountCommonPath"
generate "love.filesystem.getFullCommonPath"
generate "love.filesystem.getWorkingDirectory"
generate "love.filesystem.getUserDirectory"
generate "love.filesystem.getAppdataDirectory"
generate "love.filesystem.getSourceBaseDirectory"
generate "love.filesystem.getRealDirectory"
generate "love.filesystem.canonicalizeRealPath"
generate "love.filesystem.getExecutablePath"
generate "love.filesystem.exists"
generate "love.filesystem.setSymlinksEnabled"
generate "love.filesystem.areSymlinksEnabled"
bound_by_hand "love.filesystem.getRequirePath",
  reason: "joins the path's elements with semicolons in a loop, which the generator does not port"
bound_by_hand "love.filesystem.setRequirePath",
  reason: "splits its argument at semicolons in a loop (std::getline), which the generator does not port"
bound_by_hand "love.filesystem.getCRequirePath",
  reason: "joins the path's elements in a loop, as love.filesystem.getRequirePath"
bound_by_hand "love.filesystem.setCRequirePath",
  reason: "splits its argument in a loop, as love.filesystem.setRequirePath"
bound_by_hand "love.filesystem.getDirectoryItems",
  reason: "fills a table in a loop, which the generator does not port; Lota returns the names as an Array"
bound_by_hand "love.filesystem.mount",
  reason: "reads its arguments at positions it computes (startidx), as a Data, a FileData, a NativeFile, or " \
    "a path; Lota binds the path and Data forms, which Lota::Filesystem.mount chooses between"
bound_by_hand "love.filesystem.unmount",
  reason: "reads its argument as a Data or a string (luax_istype); Lota binds each form, which " \
    "Lota::Filesystem.unmount chooses between"
bound_by_hand "love.filesystem.append",
  reason: "returns w_write_or_append, as love.filesystem.write; Lota binds the two forms as two functions"

# love.graphics
generate "love.graphics.isActive"
generate "love.graphics.isCreated"
generate "love.graphics.reset"
generate "love.graphics.origin"
bound_by_hand "love.graphics.push",
  reason: "tests its stack type's const char * as a bool (if (sname && ...)), which clang-tidy's " \
    "readability-implicit-bool-conversion refuses; Lota binds it with a stack type and a Transform, either " \
    "of which may be nil"
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
generate "Texture:getTextureType"
generate "Texture:getLayerCount"
generate "Texture:getMipmapCount"
generate "Texture:getDPIScale"
generate "Texture:isFormatLinear"
generate "Texture:isCompressed"
generate "Texture:getMSAA"
generate "Texture:setFilter"
generate "Texture:getFilter"
generate "Texture:setMipmapFilter"
generate "Texture:getMipmapFilter"
generate "Texture:setWrap"
generate "Texture:getWrap"
generate "Texture:getFormat"
generate "Texture:isComputeWritable"
generate "Texture:isReadable"
generate "Texture:getMipmapMode"
generate "Texture:getDepthSampleMode"
generate "Texture:setDepthSampleMode"
generate "Texture:generateMipmaps"
generate "Texture:getDebugName"
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
generate "Quad:getLayer"
bound_by_hand "love.graphics.newQuad",
  reason: "chooses among its forms by its arguments' kinds, reading argument 5 as a Texture, a layer, or a " \
    "width; Lota::Graphics::Quad.new chooses as it does, and binds the forms with a texture and with numbers"
bound_by_hand "love.graphics.newSpriteBatch",
  reason: "gives its size the default 1000, which clang-tidy's readability-magic-numbers refuses in a Rice " \
    "default, and reads a usage hint whose header (graphics/vertex.h) the generator does not find, as " \
    "misc-include-cleaner asks; Lota binds the same form"
bound_by_hand "SpriteBatch:add",
  reason: "reads its placement through luax_checkstandardtransform, at a position that depends on whether a " \
    "Quad comes first; Lota binds the Quad or nil and the nine numbers as an Array, as draw"
bound_by_hand "SpriteBatch:set",
  reason: "reads its Quad and placement as SpriteBatch:add does"
generate "SpriteBatch:getTexture"
generate "SpriteBatch:getDrawRange"
bound_by_hand "Texture:getWidth",
  reason: "reads its mipmap through w__optMipmap, which the generator does not port"
bound_by_hand "Texture:getHeight",
  reason: "reads its mipmap through w__optMipmap, as Texture:getWidth"
bound_by_hand "Texture:getDimensions",
  reason: "reads its mipmap through w__optMipmap, as Texture:getWidth; Lota::Graphics::Texture#dimensions " \
    "calls the bound width and height"
bound_by_hand "Texture:getDepth",
  reason: "reads its mipmap through w__optMipmap, as Texture:getWidth"
bound_by_hand "Texture:getPixelWidth",
  reason: "reads its mipmap through w__optMipmap, as Texture:getWidth"
bound_by_hand "Texture:getPixelHeight",
  reason: "reads its mipmap through w__optMipmap, as Texture:getWidth"
bound_by_hand "Texture:getPixelDimensions",
  reason: "reads its mipmap through w__optMipmap, as Texture:getWidth; Lota::Graphics::Texture#pixel_dimensions " \
    "calls the bound pixel_width and pixel_height"
bound_by_hand "Texture:replacePixels",
  reason: "reads an ImageData or a CompressedImageData by its type (luax_istype), and its slice only for a " \
    "texture that is not 2D; Lota binds the ImageData, and the arguments after it as an Array"
bound_by_hand "love.graphics.setColor",
  reason: "LÖVE assigns each component in a statement of its own, so the port's four numbers fail clang-tidy's " \
    "bugprone-easily-swappable-parameters; Lota binds the form with separate numbers in one constructor call"
bound_by_hand "love.graphics.present",
  reason: "passes LÖVE's lua_State to Graphics::present for its screenshot callbacks, which Lota replaces " \
    "with deliver_screenshot"
bound_by_hand "love.graphics.newCanvas",
  reason: "reads its settings table through luax_checktexturesettings, at a position it computes; " \
    "Lota::Graphics::TextureSettings reads the keywords into a bound Texture::Settings, and Lota binds the rest"
bound_by_hand "love.graphics.newImage",
  reason: "LÖVE 12 makes it with w_newTexture (wrap_Graphics.cpp:1251-1255); Lota::Graphics::Image.new calls " \
    "Lota::Graphics::Texture.new, bound with newTexture"
bound_by_hand "love.graphics.newTexture",
  reason: "chooses among its forms by its arguments' kinds, and reads its images through getImageData and " \
    "luax_getdata, which the generator does not port; Lota binds every form, its settings as newCanvas's"
bound_by_hand "love.graphics.newArrayImage",
  reason: "LÖVE 12 makes it with w_newArrayTexture, which chooses among its forms as newTexture does; " \
    "Lota::Graphics::ArrayImage.new binds every form"
bound_by_hand "love.graphics.newCubeImage",
  reason: "LÖVE 12 makes it with w_newCubeTexture, which chooses among its forms as newTexture does; " \
    "Lota::Graphics::CubeImage.new binds every form"
bound_by_hand "love.graphics.newVolumeImage",
  reason: "LÖVE 12 makes it with w_newVolumeTexture, which chooses among its forms as newTexture does; " \
    "Lota::Graphics::VolumeImage.new binds every form"
bound_by_hand "love.graphics.setCanvas",
  reason: "chooses among its forms by its arguments' kinds and count, and reads a table of targets and options; " \
    "Lota binds its arguments as an Array, and the table of targets with its options as keywords"
bound_by_hand "love.graphics.clear",
  reason: "reads its stencil and depth at a position it computes (startidx)"
bound_by_hand "love.graphics.readbackTexture",
  reason: "reads its slice only for a texture that is not 2D, and its rectangle and destination only when " \
    "given; Lota binds the arguments after the texture as an Array"
bound_by_hand "love.graphics.newFont",
  reason: "chooses among its forms by its arguments' kinds, and makes its Rasterizer through love.font's " \
    "wrap functions (w_newRasterizer, w_newTrueTypeRasterizer), which read a settings table; Lota binds the " \
    "default font at a size, a TrueType font in FileData at a size, and a font from FileData alone"
generate "love.graphics.getFont"
generate "love.graphics.getDefaultFilter"
bound_by_hand "love.graphics.print",
  reason: "reads its text through luax_checkcoloredstring and its placement through " \
    "luax_checkstandardtransform, at positions that depend on whether a Font comes first; Lota binds the " \
    "form with the nine numbers, with its text and numbers as Arrays, and the form with a Transform, each with " \
    "a Font or nil"
bound_by_hand "love.graphics.printf",
  reason: "reads its text, Font, placement, and alignment at positions it computes; Lota binds the forms " \
    "with the numbers and with a Transform, as print"
bound_by_hand "love.graphics.draw",
  reason: "reads its placement at a position that depends on whether a Quad comes second; Lota binds a " \
    "Texture, a SpriteBatch, a TextBatch, and a Texture through a Quad, each with its nine numbers as an Array, as print, " \
    "or with a Transform"
bound_by_hand "love.graphics.drawLayer",
  reason: "reads its placement at a position that depends on whether a Quad comes third, as draw; Lota binds " \
    "the Quad or nil, and the nine numbers as an Array or a Transform"
bound_by_hand "love.graphics.line",
  reason: "reads its coordinates in a loop over every argument, or from a table; Lota::Graphics.line passes " \
    "them as one Array"
bound_by_hand "love.graphics.arc",
  reason: "reads its position at an index that depends on whether an arc mode comes second; " \
    "Lota::Graphics.arc passes the arc mode or nil"
generate "love.graphics.setBlendMode"
generate "love.graphics.getBlendMode"
generate "love.graphics.setColorMask"
generate "love.graphics.getColorMask"
generate "love.graphics.setDepthMode"
generate "love.graphics.getDepthMode"
generate "love.graphics.setFrontFaceWinding"
generate "love.graphics.getFrontFaceWinding"
generate "love.graphics.setLineJoin"
generate "love.graphics.getLineJoin"
generate "love.graphics.setMeshCullMode"
generate "love.graphics.getMeshCullMode"
generate "love.graphics.setPointSize"
generate "love.graphics.getPointSize"
generate "love.graphics.getScissor"
bound_by_hand "love.graphics.intersectScissor",
  reason: "assigns each side of its rectangle in a statement of its own, so the port's four numbers fail clang-tidy's " \
    "bugprone-easily-swappable-parameters, as love.graphics.setScissor's do; Lota binds them in one initializer"
generate "love.graphics.getStackDepth"
generate "love.graphics.setStencilState"
generate "love.graphics.getStencilState"
generate "love.graphics.isGammaCorrect"
generate "love.graphics.setWireframe"
generate "love.graphics.isWireframe"
generate "love.graphics.getRendererInfo"
bound_by_hand "love.graphics.setBackgroundColor",
  reason: "reads its color from a table or from numbers, and assigns each component in a statement of its own, " \
    "so the port's four numbers fail clang-tidy's bugprone-easily-swappable-parameters, as " \
    "love.graphics.setColor's do; Lota binds the form with separate numbers in one constructor call"
bound_by_hand "love.graphics.setScissor",
  reason: "chooses its form by a count of the arguments it keeps in a variable and by whether all four are " \
    "nil, and assigns each side in a statement of its own, as love.graphics.setColor does; Lota binds a " \
    "rectangle (set_scissor) and none (reset_scissor)"
bound_by_hand "love.graphics.getCanvas",
  reason: "returns as many values as it has targets, or a table it builds with pushRenderTarget, which the " \
    "generator does not port; Lota binds whether it returns a table, and each target's fields, which " \
    "Lota::Graphics.canvas returns as an Array"
bound_by_hand "love.graphics.points",
  reason: "reads its coordinates in a loop over every argument, from a table, or from a table of tables with " \
    "colors; Lota::Graphics.points passes the numbers as one Array, as line, and the form with colors waits " \
    "for a game that needs it"
bound_by_hand "love.graphics.polygon",
  reason: "reads its coordinates in a loop over every argument after the draw mode, or from a table; " \
    "Lota::Graphics.polygon passes them as one Array, as line"
generate "love.graphics.rotate"
bound_by_hand "love.graphics.applyTransform",
  reason: "reads a Transform or nine numbers through luax_checkstandardtransform, a template that hands the " \
    "matrix it builds to a lambda, which the parser does not read; Lota binds a Transform, and the nine " \
    "numbers as an Array, as draw"
bound_by_hand "love.graphics.replaceTransform",
  reason: "reads a Transform or nine numbers through luax_checkstandardtransform, as love.graphics.applyTransform"
bound_by_hand "love.graphics.transformPoint",
  reason: "assigns its point's x and y in statements of their own, so its two numbers fail clang-tidy's " \
    "bugprone-easily-swappable-parameters, as love.graphics.setColor's do; Lota makes the point from both " \
    "at once"
bound_by_hand "love.graphics.inverseTransformPoint",
  reason: "assigns its point's x and y in statements of their own, as love.graphics.transformPoint"
bound_by_hand "love.graphics.setProjection",
  reason: "reads a Transform, or a matrix layout and its elements at a position it computes (idx) through " \
    "luax_checkmatrix, which reads them in loops from the arguments or from tables; Lota binds a Transform, " \
    "and the layout and the sixteen numbers as an Array"
generate "love.graphics.resetProjection"
generate "love.graphics.getDPIScale"
generate "love.graphics.getPixelWidth"
generate "love.graphics.getPixelHeight"
generate "love.graphics.getPixelDimensions"
generate "love.graphics.flushBatch"
bound_by_hand "love.graphics.captureScreenshot",
  reason: "takes a Lua function, a Channel, or a filename, and keeps the function or the file's name to use " \
    "once the frame is presented; Lota binds a Ruby callable and a filename, and the Channel form waits for " \
    "story 7's Ractor channels"
bound_by_hand "love.graphics.getStats",
  reason: "fills in a table it is given or makes, field by field (lua_setfield), which the generator does not " \
    "port; Lota returns the fields as a Hash, which Lota::Graphics.stats makes a frozen Data (rule 10)"
bound_by_hand "love.graphics.getSupported",
  reason: "fills in a table with a field for each feature, in a loop over the features' names, as " \
    "love.graphics.getStats fills its own"
bound_by_hand "love.graphics.getSystemLimits",
  reason: "fills in a table with a field for each limit, in a loop over the limits' names, as " \
    "love.graphics.getStats fills its own"
bound_by_hand "love.graphics.getTextureFormats",
  reason: "reads its settings from the fields of a table (luax_checkboolflag, lua_getfield) and fills in a " \
    "table with a field for each pixel format, in a loop; Lota::Graphics.texture_formats takes the settings " \
    "as keywords (rule 10)"
bound_by_hand "love.graphics.getTextureTypes",
  reason: "fills in a table with a field for each texture type, in a loop over the types' names, as " \
    "love.graphics.getStats fills its own"
generate "love.graphics.setShader"
generate "love.graphics.getShader"
bound_by_hand "love.graphics.newShader",
  reason: "reads its sources from strings, files, or FileData and its options table in w_getShaderSource, " \
    "and rewrites a compile error through _transformGLSLErrorMessages in wrap_Graphics.lua; " \
    "Lota::Graphics::Shader.new ports both to Ruby, and Lota binds the shader from the sources and defines"
bound_by_hand "love.graphics.validateShader",
  reason: "reads its sources and options through w_getShaderSource, as love.graphics.newShader, and returns " \
    "a message from a catch block, which the generator does not port"
generate "Shader:getWarnings"
generate "Shader:hasUniform"
generate "Shader:hasStage"
generate "Shader:getLocalThreadgroupSize"
generate "Shader:getDebugName"
bound_by_hand "Shader:send",
  reason: "reads every argument after the name by its Lua type and by the uniform's type, at positions it " \
    "computes, into the uniform's union of memory; Lota binds the values as one Array"
bound_by_hand "Shader:sendColor",
  reason: "reads its values as Shader:send does, clamped and gamma-corrected"

# love.graphics: meshes, buffers, and particles
bound_by_hand "love.graphics.newComputeShader",
  reason: "reads its source and options through w_getShaderSource and rewrites a compile error through " \
    "_transformGLSLErrorMessages, as love.graphics.newShader; Lota::Graphics::ComputeShader.new ports both " \
    "through Shader, and Lota binds the shader from the source and defines"
bound_by_hand "Mesh:getAttachedAttributes",
  reason: "builds a table of tables with lua_createtable and lua_setfield, and at the pinned commit sets each " \
    "attribute's table into itself (wrap_Mesh.cpp:412), so it returns an empty table, which Lota returns as an empty Array"
bound_by_hand "love.graphics.newBuffer",
  reason: "reads its format and data from Lua tables of tables, flat tables, Data, or a count, and its settings " \
    "from table fields (luax_newbuffer, luax_checkbufferformat), which the parser does not read; " \
    "Lota::Graphics::Buffer.new reads the keywords and the format and Lota binds the buffer from the " \
    "declarations, the uses, and the content"
bound_by_hand "love.graphics.newMesh",
  reason: "chooses among three forms by the types of its arguments and reads vertices from Lua tables " \
    "(newStandardMesh, newCustomMesh, newMeshFromBuffers); Lota::Graphics::Mesh.new chooses the form and " \
    "Lota binds each"
bound_by_hand "love.graphics.drawInstanced",
  reason: "reads a Transform or nine numbers through luax_checkstandardtransform, a template that hands the " \
    "matrix to a callback, as love.graphics.applyTransform"
bound_by_hand "love.graphics.drawIndirect",
  reason: "reads a Transform or nine numbers through luax_checkstandardtransform, as love.graphics.drawInstanced"
bound_by_hand "love.graphics.dispatchThreadgroups",
  reason: "gives its second and third counts the default 1, which clang-tidy's readability-magic-numbers " \
    "refuses in a Rice default; Lota binds them as optional integers"
bound_by_hand "love.graphics.dispatchIndirect",
  reason: "gives its argument index the default 1, as love.graphics.dispatchThreadgroups"
bound_by_hand "Buffer:setArrayData",
  reason: "writes from Lua tables or a Data into mapped memory through luax_writebufferdata, reading the stack " \
    "at positions it computes; Lota reads the Arrays Lota::Graphics::Buffer passes"
bound_by_hand "Buffer:getFormat",
  reason: "fills in a table with a table for each member (lua_createtable, lua_setfield), which the generator " \
    "does not port; Lota returns each member's fields, which Lota::Graphics::Buffer makes a frozen Data"
bound_by_hand "Mesh:setVertices",
  reason: "writes from Lua tables or a Data through luax_writebufferdata, reading the stack at positions it " \
    "computes"
bound_by_hand "Mesh:setVertex",
  reason: "writes a vertex from a table or from the stack through luax_writebufferdata"
bound_by_hand "Mesh:getVertex",
  reason: "pushes a computed number of values through luax_readbufferdata"
bound_by_hand "Mesh:setVertexAttribute",
  reason: "writes an attribute from the stack through luax_writebufferdata"
bound_by_hand "Mesh:getVertexAttribute",
  reason: "pushes a computed number of values through luax_readbufferdata"
bound_by_hand "Mesh:getVertexFormat",
  reason: "fills in a table with a table for each attribute (lua_createtable, lua_setfield), as Buffer:getFormat"
bound_by_hand "Mesh:setAttributeEnabled",
  reason: "chooses its form by the type of argument 2 (lua_type), a name or a binding location"
bound_by_hand "Mesh:isAttributeEnabled",
  reason: "chooses its form by the type of argument 2, as Mesh:setAttributeEnabled"
bound_by_hand "Mesh:attachAttribute",
  reason: "chooses its form by the type of argument 2 and of argument 3, a Buffer or a Mesh, and reads " \
    "optional arguments at positions that depend on the form"
bound_by_hand "Mesh:setVertexMap",
  reason: "chooses its form by its arguments' kinds, a table, a Data, a list on the stack, or nothing " \
    "(lua_istable, luax_istype, lua_gettop); Lota binds the three that remain"
bound_by_hand "Mesh:getVertexMap",
  reason: "pushes a table built with lua_createtable, or nil"
bound_by_hand "ParticleSystem:setSizes",
  reason: "reads a count of values from the stack (lua_gettop) and chooses setSize or setSizes by it"
bound_by_hand "ParticleSystem:getSizes",
  reason: "returns a computed number of values (return (int) sizes.size())"
bound_by_hand "ParticleSystem:setColors",
  reason: "reads its colors from Lua tables or from the stack, choosing by lua_istable and lua_gettop"
bound_by_hand "ParticleSystem:getColors",
  reason: "returns a computed number of tables (return (int) colors.size())"
bound_by_hand "ParticleSystem:setQuads",
  reason: "reads its Quads from a table or from the stack, choosing by lua_istable"
bound_by_hand "ParticleSystem:getQuads",
  reason: "pushes a table of objects built with lua_createtable"
bound_by_hand "Shader:getBufferFormat",
  reason: "fills in a table with a table for each member (lua_createtable, lua_setfield), as Buffer:getFormat"
bound_by_hand "love.graphics.newParticleSystem",
  reason: "reads its size as a lua_Number and casts it twice, which the port writes as redundant and C-style " \
    "casts that clang-tidy's readability-redundant-casting and modernize-avoid-c-style-cast refuse"
bound_by_hand "Buffer:clear",
  reason: "casts a lua_Number to size_t with C-style casts, which clang-tidy's modernize-avoid-c-style-cast " \
    "refuses; Lota binds the offset and size as one Array"
bound_by_hand "Buffer:isBufferType",
  reason: "shifts a signed 1 by the buffer usage, which clang-tidy's bugprone-signed-bitwise refuses"
bound_by_hand "ParticleSystem:setBufferSize",
  reason: "reads its size as a lua_Number and casts it to uint32 with a C-style cast, as love.graphics.newParticleSystem"
bound_by_hand "ParticleSystem:getPosition",
  reason: "copies the Vector2 the engine returns by reference, which clang-tidy's " \
    "performance-unnecessary-copy-initialization refuses, and the port does not include Vector's header"
generate "love.graphics.getQuadIndexBuffer"
generate "Buffer:getElementCount"
generate "Buffer:getElementStride"
generate "Buffer:getSize"
generate "Buffer:getDebugName"
generate "Mesh:getVertexCount"
generate "Mesh:detachAttribute"
generate "Mesh:getVertexBuffer"
generate "Mesh:flush"
generate "Mesh:setIndexBuffer"
generate "Mesh:getIndexBuffer"
generate "Mesh:setTexture"
generate "Mesh:getTexture"
generate "Mesh:setDrawMode"
generate "Mesh:getDrawMode"
generate "Mesh:setDrawRange"
generate "Mesh:getDrawRange"
generate "ParticleSystem:clone"
generate "ParticleSystem:setTexture"
generate "ParticleSystem:getTexture"
generate "ParticleSystem:getBufferSize"
generate "ParticleSystem:setInsertMode"
generate "ParticleSystem:getInsertMode"
generate "ParticleSystem:setEmissionRate"
generate "ParticleSystem:getEmissionRate"
generate "ParticleSystem:setEmitterLifetime"
generate "ParticleSystem:getEmitterLifetime"
generate "ParticleSystem:setParticleLifetime"
generate "ParticleSystem:getParticleLifetime"
generate "ParticleSystem:setPosition"
generate "ParticleSystem:moveTo"
generate "ParticleSystem:setEmissionArea"
generate "ParticleSystem:getEmissionArea"
generate "ParticleSystem:setDirection"
generate "ParticleSystem:getDirection"
generate "ParticleSystem:setSpread"
generate "ParticleSystem:getSpread"
generate "ParticleSystem:setSpeed"
generate "ParticleSystem:getSpeed"
generate "ParticleSystem:setLinearAcceleration"
generate "ParticleSystem:getLinearAcceleration"
generate "ParticleSystem:setRadialAcceleration"
generate "ParticleSystem:getRadialAcceleration"
generate "ParticleSystem:setTangentialAcceleration"
generate "ParticleSystem:getTangentialAcceleration"
generate "ParticleSystem:setLinearDamping"
generate "ParticleSystem:getLinearDamping"
generate "ParticleSystem:setSizeVariation"
generate "ParticleSystem:getSizeVariation"
generate "ParticleSystem:setRotation"
generate "ParticleSystem:getRotation"
generate "ParticleSystem:setSpin"
generate "ParticleSystem:getSpin"
generate "ParticleSystem:setSpinVariation"
generate "ParticleSystem:getSpinVariation"
generate "ParticleSystem:setOffset"
generate "ParticleSystem:getOffset"
generate "ParticleSystem:setRelativeRotation"
generate "ParticleSystem:hasRelativeRotation"
generate "ParticleSystem:getCount"
generate "ParticleSystem:start"
generate "ParticleSystem:stop"
generate "ParticleSystem:pause"
generate "ParticleSystem:reset"
generate "ParticleSystem:emit"
generate "ParticleSystem:isActive"
generate "ParticleSystem:isPaused"
generate "ParticleSystem:isStopped"
generate "ParticleSystem:update"

# love.image
bound_from_lua "ImageData:getWidth"
bound_from_lua "ImageData:getHeight"
bound_from_lua "ImageData:getPixel"
bound_from_lua "ImageData:setPixel"
bound_from_lua "ImageData:mapPixel"
bound_from_lua "ImageData:getDimensions"
bound_from_lua "ImageData:getFormat"
generate "ImageData:clone"
generate "ImageData:encode"
generate "ImageData:paste"
generate "ImageData:isLinear"
generate "ImageData:setLinear"
bound_by_hand "love.image.newImageData",
  reason: "chooses among its forms by its arguments' kinds, and reads raw bytes from a string or any Data " \
    "(luax_istype); Lota binds the form that decodes Data and the form with a size, a pixel format, and bytes"

# love.joystick
bound_by_hand "love.joystick.getJoysticks",
  reason: "builds a table of Joysticks with lua_createtable and lua_rawseti in a loop, which the generator does " \
    "not port; Lota returns them as an Array"
bound_by_hand "love.joystick.loadGamepadMappings",
  reason: "reads a file through luax_getfiledata when LÖVE's filesystem finds one of that name, which the " \
    "generator does not port"
bound_by_hand "love.joystick.saveGamepadMappings",
  reason: "reads the stack at a position it computes to write the file through luax_convobj; Lota binds the " \
    "string, and Lota::Joystick.save_gamepad_mappings writes it with Lota::Filesystem.write"
generate "love.joystick.getJoystickCount"
generate "love.joystick.setBackgroundEvents"
generate "love.joystick.hasBackgroundEvents"
bound_by_hand "love.joystick.setGamepadMapping",
  reason: "reads its fourth and fifth arguments in a switch on the input type, which the generator " \
    "does not port"
generate "love.joystick.getGamepadMappingString"
generate "Joystick:isConnected"
generate "Joystick:getName"
generate "Joystick:getID"
generate "Joystick:getGUID"
generate "Joystick:getDeviceInfo"
generate "Joystick:getDevicePowerInfo"
generate "Joystick:getDeviceConnectionState"
generate "Joystick:getJoystickType"
generate "Joystick:getAxisCount"
generate "Joystick:getButtonCount"
generate "Joystick:getHatCount"
generate "Joystick:getAxis"
bound_by_hand "Joystick:getAxes",
  reason: "returns a computed number of values, one for each axis; Lota returns them as an Array"
generate "Joystick:getHat"
bound_by_hand "Joystick:isDown",
  reason: "reads its buttons in a loop over every argument, or from a table; Lota::Joystick::Joystick#down? " \
    "passes them as one Array"
generate "Joystick:setPlayerIndex"
bound_by_hand "Joystick:getPlayerIndex",
  reason: "pushes index >= 0 ? index + 1 : index, whose type the generator cannot tell from the headers"
generate "Joystick:isGamepad"
generate "Joystick:getGamepadType"
generate "Joystick:getGamepadAxis"
bound_by_hand "Joystick:isGamepadDown",
  reason: "reads its buttons in a loop over every argument, or from a table, as Joystick:isDown"
bound_by_hand "Joystick:getGamepadMapping",
  reason: "returns none, two, or three values from a switch on the input type, which the generator " \
    "does not port; Lota returns them as an Array, empty for none"
generate "Joystick:getGamepadMappingString"
generate "Joystick:isVibrationSupported"
bound_by_hand "Joystick:setVibration",
  reason: "the generator reads its left motor into a local where LÖVE checks it, which leaves clang-tidy's " \
    "bugprone-easily-swappable-parameters seeing the left and right motors used apart; Lota reads both in " \
    "the one call, as LÖVE does"
generate "Joystick:getVibration"
generate "Joystick:hasSensor"
generate "Joystick:isSensorEnabled"
generate "Joystick:setSensorEnabled"
bound_by_hand "Joystick:getSensorData",
  reason: "returns a computed number of values, one for each the sensor reads; Lota returns them as an Array"
generate "Joystick:getConnectedIndex"

# love.keyboard
bound_by_hand "love.keyboard.isDown",
  reason: "reads its keys in a loop over every argument, or from a table; Lota::Keyboard.down? passes them " \
    "as one Array"
generate "love.keyboard.setKeyRepeat"
generate "love.keyboard.hasKeyRepeat"
generate "love.keyboard.setTextInput"
generate "love.keyboard.hasTextInput"
generate "love.keyboard.hasScreenKeyboard"
generate "love.keyboard.isScreenKeyboardVisible"
bound_by_hand "love.keyboard.isScancodeDown",
  reason: "reads its scancodes in a loop over every argument, or from a table, as love.keyboard.isDown; " \
    "Lota::Keyboard.scancode_down? passes them as one Array"
generate "love.keyboard.getScancodeFromKey"
generate "love.keyboard.getKeyFromScancode"
generate "love.keyboard.isModifierActive"

# love.mouse
generate "love.mouse.getSystemCursor"
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
generate "love.mouse.getCursor"
bound_by_hand "love.mouse.newCursor",
  reason: "reads one image or a table of them, each converted to an ImageData through luax_convobj, and " \
    "releases them in luax_catchexcept's cleanup; Lota::Mouse::Cursor.new makes the ImageData and binds " \
    "the form of an Array of them"
bound_by_hand "Cursor:getType",
  reason: "Lota::Native defines Cursor under its Mouse module, and the generator defines each class it binds " \
    "directly under Lota::Native"

# love.math
bound_by_hand "RandomGenerator:_random",
  reason: "clang-analyzer's security.insecureAPI.rand takes the port's call to a method named random for the C " \
    "library's random(), so Lota binds the method itself, as random"
bound_from_lua "RandomGenerator:randomNormal"
generate "RandomGenerator:getState"
generate "RandomGenerator:setState"
generate "love.math.newTransform"
generate "Transform:clone"
generate "Transform:inverse"
generate "Transform:inverseOf"
generate "Transform:apply"
generate "Transform:isAffine2DTransform"
generate "Transform:__mul"
generate "Transform:translate"
generate "Transform:rotate"
generate "Transform:scale"
generate "Transform:shear"
generate "Transform:reset"
generate "Transform:setTransformation"
bound_by_hand "Transform:setMatrix",
  reason: "reads its matrix layout and elements at a position it computes (idx) through luax_checkmatrix, as " \
    "love.graphics.setProjection; Lota binds the layout and the sixteen numbers as an Array"
bound_by_hand "Transform:getMatrix",
  reason: "pushes its sixteen elements in a loop, which the generator does not port; Lota returns them as an " \
    "Array in the same order"
bound_by_hand "Transform:transformPoint",
  reason: "assigns its point's x and y in statements of their own, as love.graphics.transformPoint"
bound_by_hand "Transform:inverseTransformPoint",
  reason: "assigns its point's x and y in statements of their own, as love.graphics.transformPoint"
bound_by_hand "love.math.newRandomGenerator",
  reason: "reads its seed's two halves at a position it computes; Lota binds the generator's constructor"
bound_by_hand "love.math._getRandomGenerator",
  reason: "no rule names it, as its leading underscore keeps it to wrap_Math.lua, and a name no rule gives is " \
    "the maintainer's to give; Lota::Math draws from it, as wrap_Math.lua does"
bound_by_hand "RandomGenerator:setSeed",
  reason: "reads its seed's two halves at a position it computes (luax_checkrandomseed); Lota binds the low " \
    "half and an optional high half"
bound_by_hand "RandomGenerator:getSeed",
  reason: "pushes the halves of its seed's union (s.b32.low and high), whose fields the headers do not type " \
    "for the generator; Lota binds them as an Array of two Integers"
bound_by_hand "love.math.newBezierCurve",
  reason: "reads its points from a table or from every argument in a loop, at positions it computes; Lota " \
    "binds them as an Array"
bound_by_hand "love.math.triangulate",
  reason: "reads its vertices as love.math.newBezierCurve reads its points, and returns a table of tables it " \
    "fills in a loop; Lota returns an Array of Arrays"
bound_by_hand "love.math.isConvex",
  reason: "reads its vertices as love.math.newBezierCurve reads its points"
bound_from_lua "love.math.gammaToLinear"
bound_from_lua "love.math.linearToGamma"
bound_from_lua "love.math.noise"
bound_from_lua "love.math.perlinNoise"
bound_from_lua "love.math.simplexNoise"
generate "BezierCurve:getDegree"
generate "BezierCurve:getDerivative"
bound_by_hand "BezierCurve:getControlPoint",
  reason: "copies the point getControlPoint returns by const reference into a const Vector2, which " \
    "clang-tidy's performance-unnecessary-copy-initialization refuses; Lota reads it through the reference"
generate "BezierCurve:setControlPoint"
generate "BezierCurve:insertControlPoint"
generate "BezierCurve:removeControlPoint"
generate "BezierCurve:getControlPointCount"
generate "BezierCurve:translate"
generate "BezierCurve:rotate"
generate "BezierCurve:scale"
generate "BezierCurve:evaluate"
generate "BezierCurve:getSegment"
bound_by_hand "BezierCurve:render",
  reason: "fills a table with the points it renders in a loop, which the generator does not port; Lota returns " \
    "their coordinates as one Array"
bound_by_hand "BezierCurve:renderSegment",
  reason: "fills a table in a loop, as BezierCurve:render"

# love.physics, as Lota's physics patch leaves it (ext/lota/engine/physics.patch).
generate "Body:getX"
generate "Body:getY"
generate "Body:setX"
generate "Body:setY"
generate "Body:getPosition"
generate "Body:setPosition"
generate "Body:getAngle"
generate "Body:setAngle"
generate "Body:isActive"
generate "Body:isBullet"
generate "Body:setBullet"
generate "Body:isFixedRotation"
generate "Body:setFixedRotation"
generate "Body:isSleepingAllowed"
generate "Body:setSleepingAllowed"
generate "Body:isAwake"
generate "Body:getType"
generate "Body:setType"
generate "Body:isTouching"
generate "Body:getLocalCenter"
generate "Body:getLocalPoint"
generate "Body:getWorldPoint"
generate "Body:getAngularDamping"
generate "Body:getAngularVelocity"
generate "Body:getWorldCenter"
generate "Body:getWorldVector"
generate "Body:getInertia"
generate "Body:getGravityScale"
generate "Body:setGravityScale"
generate "Body:getLinearDamping"
generate "Body:setLinearDamping"
generate "Body:getLinearVelocity"
generate "Body:setLinearVelocity"
generate "Body:getMass"
generate "Body:setMass"
generate "Body:setMassData"
generate "Body:resetMassData"
generate "Body:hasCustomMassData"
generate "Body:applyAngularImpulse"
generate "Body:applyTorque"
generate "Body:isDestroyed"
generate "Body:destroy"
generate "World:getBodyCount"
generate "World:translateOrigin"
generate "World:isLocked"
generate "World:isSleepingAllowed"
generate "World:setSleepingAllowed"
generate "World:getJointCount"
generate "World:setGravity"
generate "World:getContactCount"
generate "World:isDestroyed"
generate "World:destroy"
generate "Shape:getType"
generate "Shape:getChildCount"
generate "Shape:getRadius"
generate "Shape:isSensor"
generate "Shape:setSensor"
generate "Shape:isDestroyed"
generate "Shape:getDensity"
generate "Shape:setDensity"
generate "Shape:getFriction"
generate "Shape:setFriction"
generate "Shape:getRestitution"
generate "Shape:setRestitution"
generate "Shape:testPoint"
generate "Shape:getGroupIndex"
generate "Shape:setGroupIndex"
generate "Shape:destroy"
generate "Joint:getType"
generate "Joint:isDestroyed"
generate "Joint:getReactionTorque"
generate "Joint:getCollideConnected"
generate "Joint:destroy"
generate "Contact:getChildren"
generate "Contact:isTouching"
generate "Contact:isEnabled"
generate "Contact:setEnabled"
generate "Contact:getFriction"
generate "Contact:setFriction"
generate "Contact:resetFriction"
generate "Contact:getRestitution"
generate "Contact:setRestitution"
generate "Contact:resetRestitution"
generate "love.physics.setMeter"
generate "love.physics.newWorld"
generate "love.physics.newBody"
bound_by_hand "love.physics.newCircleShape",
  reason: "reads its numbers at positions that depend on whether a Body comes first (bodyidx) and chooses its " \
    "form by their count; Lota::Physics::CircleShape.new chooses by the count, and binds the form with a " \
    "Body"
bound_by_hand "love.physics.newRectangleShape",
  reason: "reads its numbers at positions that depend on whether a Body comes first, as newCircleShape; " \
    "Lota::Physics::RectangleShape.new chooses its form by their count, and binds the numbers as an Array"
bound_by_hand "love.physics.newEdgeShape",
  reason: "reads its numbers at positions that depend on whether a Body comes first, as newCircleShape; Lota " \
    "binds them as an Array"
bound_by_hand "love.physics.newPolygonShape",
  reason: "reads its vertices in a loop over every argument, or from a table; Lota::Physics::PolygonShape.new " \
    "passes them as one Array"
bound_by_hand "love.physics.newChainShape",
  reason: "reads its vertices in a loop over every argument, or from a table, as newPolygonShape"
generate "love.physics.newDistanceJoint"
bound_by_hand "love.physics.newFrictionJoint",
  reason: "reads argument 5 as a number in one form and as a boolean in the other, choosing the form by " \
    "lua_gettop, which counts an argument given as nil, where Rice passes one C++ type for each argument and nil " \
    "as none; Lota::Physics::FrictionJoint.new chooses by the count of its numbers, which Lota binds as an Array"
generate "love.physics.newGearJoint"
generate "love.physics.newMotorJoint"
generate "love.physics.newMouseJoint"
bound_by_hand "love.physics.newPrismaticJoint",
  reason: "reads argument 7 as a number or a boolean by its form, which it chooses by lua_gettop, as " \
    "newFrictionJoint"
generate "love.physics.newPulleyJoint"
bound_by_hand "love.physics.newRevoluteJoint",
  reason: "reads argument 5 as a number or a boolean by its form, which it chooses by lua_gettop, as " \
    "newFrictionJoint"
generate "love.physics.newRopeJoint"
bound_by_hand "love.physics.newWeldJoint",
  reason: "reads argument 5 as a number or a boolean by its form, which it chooses by lua_gettop, as " \
    "newFrictionJoint"
bound_by_hand "love.physics.newWheelJoint",
  reason: "reads argument 7 as a number or a boolean by its form, which it chooses by lua_gettop, as " \
    "newFrictionJoint"
bound_by_hand "love.physics.getDistance",
  reason: "passes the lua_State to Physics::getDistance, which Lota's physics patch makes take two Shapes and " \
    "return the distance and points"
generate "love.physics.getMeter"
generate "love.physics.computeLinearStiffness"
generate "love.physics.computeLinearFrequency"
generate "love.physics.computeAngularStiffness"
generate "love.physics.computeAngularFrequency"
generate "Body:getWorld"
generate "Body:getShape"
bound_by_hand "Body:getShapes",
  reason: "passes the lua_State to Body::getShapes, which Lota's physics patch makes return a std::vector"
bound_by_hand "Body:getJoints",
  reason: "passes the lua_State to Body::getJoints, as Body:getShapes"
bound_by_hand "Body:getContacts",
  reason: "passes the lua_State to Body::getContacts, as Body:getShapes"
bound_by_hand "Body:getMassData",
  reason: "passes the lua_State to Body::getMassData, which Lota's physics patch makes fill four floats"
bound_by_hand "Body:getWorldPoints",
  reason: "passes the lua_State to Body::getWorldPoints, which Lota's physics patch makes transform a " \
    "std::vector; Lota binds the points as an Array"
bound_by_hand "Body:getLocalPoints",
  reason: "passes the lua_State to Body::getLocalPoints, as Body:getWorldPoints"
bound_by_hand "Body:setUserData",
  reason: "passes the lua_State to Body::setUserData, which held a Lua Reference; Lota's physics patch makes it " \
    "take Reference.h's Reference, which Lota implements for a Ruby value"
bound_by_hand "Body:getUserData",
  reason: "passes the lua_State to Body::getUserData, as Body:setUserData"
bound_by_hand "Body:applyForce",
  reason: "chooses its form by lua_gettop and lua_type; Lota binds the numbers and the flag after the force as " \
    "an Array"
bound_by_hand "Body:applyLinearImpulse",
  reason: "chooses its form by lua_gettop and lua_type, as Body:applyForce"
bound_by_hand "World:update",
  reason: "passes the lua_State to World::setCallbacksL, for Lua's coroutines, which Lota's physics patch " \
    "removes"
bound_by_hand "World:setCallbacks",
  reason: "passes the lua_State to World::setCallbacks, which keeps up to four Lua functions; Lota's physics " \
    "patch makes it take Reference.h's ContactFunctions, which Lota implements for Ruby callables, and " \
    "Lota::Physics::World#callbacks= takes them as one Array"
bound_by_hand "World:getCallbacks",
  reason: "passes the lua_State to World::getCallbacks, which Lota's physics patch makes give back its four " \
    "ContactFunctions, whose Ruby callables Lota returns"
bound_by_hand "World:setContactFilter",
  reason: "passes the lua_State to World::setContactFilter, which keeps a Lua function; Lota's physics patch " \
    "makes it take Reference.h's ContactFilterFunction, which Lota implements for a Ruby callable"
bound_by_hand "World:getContactFilter",
  reason: "passes the lua_State to World::getContactFilter, as World:getCallbacks"
bound_by_hand "World:getBodies",
  reason: "passes the lua_State to World::getBodies, which Lota's physics patch makes return a std::vector"
bound_by_hand "World:getJoints",
  reason: "passes the lua_State to World::getJoints, as World:getBodies"
bound_by_hand "World:getContacts",
  reason: "passes the lua_State to World::getContacts, as World:getBodies"
bound_by_hand "World:getGravity",
  reason: "passes the lua_State to World::getGravity, which Lota's physics patch makes fill two floats"
bound_by_hand "World:getShapesInArea",
  reason: "passes the lua_State to World::getShapesInArea, which Lota's physics patch makes take its numbers " \
    "and return a std::vector"
bound_by_hand "World:queryShapesInArea",
  reason: "passes the lua_State to World::queryShapesInArea, which calls a Lua function; Lota's physics patch " \
    "makes it call Reference.h's QueryFunction, which Lota implements for the block"
bound_by_hand "World:rayCast",
  reason: "passes the lua_State to World::rayCast, which calls a Lua function; Lota's physics patch makes it " \
    "call Reference.h's RayCastFunction, which Lota implements for the block"
bound_by_hand "World:rayCastAny",
  reason: "passes the lua_State to World::rayCastAny, which Lota's physics patch makes take its numbers and " \
    "return the Shape it hit"
bound_by_hand "World:rayCastClosest",
  reason: "passes the lua_State to World::rayCastClosest, as World:rayCastAny"
generate "Shape:getBody"
generate "Shape:getFilterData"
bound_by_hand "Shape:setCategory",
  reason: "passes the lua_State to Shape::setCategory, which reads every argument or a table; Lota's physics " \
    "patch makes it take a std::vector, which Lota binds as an Array"
bound_by_hand "Shape:getCategory",
  reason: "passes the lua_State to Shape::getCategory, which Lota's physics patch makes return a std::vector"
bound_by_hand "Shape:setMask",
  reason: "passes the lua_State to Shape::setMask, as Shape:setCategory"
bound_by_hand "Shape:getMask",
  reason: "passes the lua_State to Shape::getMask, as Shape:getCategory"
bound_by_hand "Shape:computeAABB",
  reason: "passes the lua_State to Shape::computeAABB, which Lota's physics patch makes take its numbers and " \
    "fill four floats"
bound_by_hand "Shape:getBoundingBox",
  reason: "passes the lua_State to Shape::getBoundingBox, as Shape:computeAABB"
bound_by_hand "Shape:computeMass",
  reason: "passes the lua_State to Shape::computeMass, as Shape:computeAABB"
bound_by_hand "Shape:getMassData",
  reason: "passes the lua_State to Shape::getMassData, as Shape:computeAABB"
bound_by_hand "Shape:rayCast",
  reason: "passes the lua_State to Shape::rayCast, which chooses its form by whether argument 7 is given; " \
    "Lota's physics patch makes it take its numbers, which Lota binds as two Arrays"
bound_by_hand "Shape:setUserData",
  reason: "passes the lua_State to Shape::setUserData, as Body:setUserData"
bound_by_hand "Shape:getUserData",
  reason: "passes the lua_State to Shape::getUserData, as Body:setUserData"
generate "Joint:getBodies"
bound_by_hand "Joint:getAnchors",
  reason: "passes the lua_State to Joint::getAnchors, which Lota's physics patch makes fill four floats"
bound_by_hand "Joint:getReactionForce",
  reason: "passes the lua_State to Joint::getReactionForce, which Lota's physics patch makes take its step and " \
    "fill two floats"
bound_by_hand "Joint:setUserData",
  reason: "passes the lua_State to Joint::setUserData, as Body:setUserData"
bound_by_hand "Joint:getUserData",
  reason: "passes the lua_State to Joint::getUserData, as Body:setUserData"
generate "Contact:getShapes"
bound_by_hand "Contact:getNormal",
  reason: "passes the lua_State to Contact::getNormal, which Lota's physics patch makes fill two floats"
bound_by_hand "Contact:getPositions",
  reason: "passes the lua_State to Contact::getPositions, which Lota's physics patch makes return a std::vector"
generate "Body:getTransform"
bound_by_hand "Body:setTransform",
  reason: "passes its position to one engine call and its angle to another, so the port's three numbers fail " \
    "clang-tidy's bugprone-easily-swappable-parameters; Lota binds them as an Array"
generate "Body:getKinematicState"
generate "Body:setKinematicState"
generate "Body:setAngularVelocity"
generate "Body:setInertia"
generate "Body:setAngularDamping"
generate "Body:getLocalVector"
generate "Body:getLinearVelocityFromWorldPoint"
generate "Body:getLinearVelocityFromLocalPoint"
generate "Body:setActive"
generate "Body:setAwake"
generate "Shape:setFilterData"
generate "CircleShape:getRadius"
generate "CircleShape:setRadius"
generate "CircleShape:getPoint"
generate "CircleShape:setPoint"
generate "ChainShape:setNextVertex"
generate "ChainShape:setPreviousVertex"
generate "ChainShape:getNextVertex"
generate "ChainShape:getPreviousVertex"
generate "ChainShape:getChildEdge"
generate "ChainShape:getVertexCount"
generate "ChainShape:getPoint"
generate "EdgeShape:setNextVertex"
generate "EdgeShape:setPreviousVertex"
generate "EdgeShape:getNextVertex"
generate "EdgeShape:getPreviousVertex"
generate "PolygonShape:validate"
bound_by_hand "PolygonShape:getPoints",
  reason: "passes the lua_State to PolygonShape::getPoints, which Lota's physics patch makes return a std::vector"
bound_by_hand "EdgeShape:getPoints",
  reason: "passes the lua_State to EdgeShape::getPoints, which Lota's physics patch makes fill four floats"
bound_by_hand "ChainShape:getPoints",
  reason: "pushes a computed number of values in a loop, one pair for each vertex; Lota returns them as an Array"
generate "Contact:setTangentSpeed"
generate "Contact:getTangentSpeed"
generate "Contact:isDestroyed"
generate "DistanceJoint:setLength"
generate "DistanceJoint:getLength"
generate "DistanceJoint:setStiffness"
generate "DistanceJoint:getStiffness"
generate "DistanceJoint:setDamping"
generate "DistanceJoint:getDamping"
generate "FrictionJoint:setMaxForce"
generate "FrictionJoint:getMaxForce"
generate "FrictionJoint:setMaxTorque"
generate "FrictionJoint:getMaxTorque"
generate "GearJoint:setRatio"
generate "GearJoint:getRatio"
generate "GearJoint:getJoints"
generate "MotorJoint:setLinearOffset"
generate "MotorJoint:setAngularOffset"
generate "MotorJoint:getAngularOffset"
generate "MotorJoint:setMaxForce"
generate "MotorJoint:getMaxForce"
generate "MotorJoint:setMaxTorque"
generate "MotorJoint:getMaxTorque"
generate "MotorJoint:setCorrectionFactor"
generate "MotorJoint:getCorrectionFactor"
bound_by_hand "MotorJoint:getLinearOffset",
  reason: "passes the lua_State to MotorJoint::getLinearOffset, which Lota's physics patch makes fill two floats"
generate "PrismaticJoint:getJointTranslation"
generate "PrismaticJoint:getJointSpeed"
generate "PrismaticJoint:setMotorEnabled"
generate "PrismaticJoint:isMotorEnabled"
generate "PrismaticJoint:setMaxMotorForce"
generate "PrismaticJoint:setMotorSpeed"
generate "PrismaticJoint:getMotorSpeed"
generate "PrismaticJoint:getMotorForce"
generate "PrismaticJoint:getMaxMotorForce"
generate "PrismaticJoint:setLimitsEnabled"
generate "PrismaticJoint:areLimitsEnabled"
generate "PrismaticJoint:setUpperLimit"
generate "PrismaticJoint:setLowerLimit"
generate "PrismaticJoint:setLimits"
generate "PrismaticJoint:getLowerLimit"
generate "PrismaticJoint:getUpperLimit"
generate "PrismaticJoint:getReferenceAngle"
bound_by_hand "PrismaticJoint:getLimits",
  reason: "passes the lua_State to PrismaticJoint::getLimits, which Lota's physics patch makes fill two floats"
bound_by_hand "PrismaticJoint:getAxis",
  reason: "passes the lua_State to PrismaticJoint::getAxis, which Lota's physics patch makes fill two floats"
generate "PulleyJoint:getLengthA"
generate "PulleyJoint:getLengthB"
generate "PulleyJoint:getRatio"
bound_by_hand "PulleyJoint:getGroundAnchors",
  reason: "passes the lua_State to PulleyJoint::getGroundAnchors, which Lota's physics patch makes fill four floats"
generate "RevoluteJoint:getJointAngle"
generate "RevoluteJoint:getJointSpeed"
generate "RevoluteJoint:setMotorEnabled"
generate "RevoluteJoint:isMotorEnabled"
generate "RevoluteJoint:setMaxMotorTorque"
generate "RevoluteJoint:setMotorSpeed"
generate "RevoluteJoint:getMotorSpeed"
generate "RevoluteJoint:getMotorTorque"
generate "RevoluteJoint:getMaxMotorTorque"
generate "RevoluteJoint:setLimitsEnabled"
generate "RevoluteJoint:areLimitsEnabled"
generate "RevoluteJoint:setUpperLimit"
generate "RevoluteJoint:setLowerLimit"
generate "RevoluteJoint:setLimits"
generate "RevoluteJoint:getLowerLimit"
generate "RevoluteJoint:getUpperLimit"
generate "RevoluteJoint:getReferenceAngle"
bound_by_hand "RevoluteJoint:getLimits",
  reason: "passes the lua_State to RevoluteJoint::getLimits, which Lota's physics patch makes fill two floats"
generate "RopeJoint:getMaxLength"
generate "RopeJoint:setMaxLength"
generate "WeldJoint:setStiffness"
generate "WeldJoint:getStiffness"
generate "WeldJoint:setDamping"
generate "WeldJoint:getDamping"
generate "WeldJoint:getReferenceAngle"
generate "WheelJoint:getJointTranslation"
generate "WheelJoint:getJointSpeed"
generate "WheelJoint:setMotorEnabled"
generate "WheelJoint:isMotorEnabled"
generate "WheelJoint:setMotorSpeed"
generate "WheelJoint:getMotorSpeed"
generate "WheelJoint:setMaxMotorTorque"
generate "WheelJoint:getMaxMotorTorque"
generate "WheelJoint:getMotorTorque"
generate "WheelJoint:setSpringStiffness"
generate "WheelJoint:getSpringStiffness"
generate "WheelJoint:setSpringDamping"
generate "WheelJoint:getSpringDamping"
generate "WheelJoint:setStiffness"
generate "WheelJoint:getStiffness"
generate "WheelJoint:setDamping"
generate "WheelJoint:getDamping"
bound_by_hand "WheelJoint:getAxis",
  reason: "passes the lua_State to WheelJoint::getAxis, which Lota's physics patch makes fill two floats"
generate "MouseJoint:setTarget"
bound_by_hand "MouseJoint:getTarget",
  reason: "passes the lua_State to MouseJoint::getTarget, which Lota's physics patch makes fill two floats"
generate "MouseJoint:setMaxForce"
generate "MouseJoint:getMaxForce"
generate "MouseJoint:setStiffness"
generate "MouseJoint:getStiffness"
generate "MouseJoint:setDamping"
generate "MouseJoint:getDamping"

# love.sensor
bound_by_hand "love.sensor.hasSensor",
  reason: "reads its sensor type through luax_checksensortype, an inline helper of wrap_Sensor.cpp that checks " \
    "the name with luax_enumerror, which the parser does not follow"
bound_by_hand "love.sensor.isEnabled",
  reason: "reads its sensor type through luax_checksensortype, an inline helper of wrap_Sensor.cpp that checks " \
    "the name with luax_enumerror, which the parser does not follow"
bound_by_hand "love.sensor.setEnabled",
  reason: "reads its sensor type through luax_checksensortype, an inline helper of wrap_Sensor.cpp that checks " \
    "the name with luax_enumerror, which the parser does not follow"
bound_by_hand "love.sensor.getData",
  reason: "returns a computed number of values, one for each the sensor reads, and reads its type as " \
    "love.sensor.hasSensor does; Lota returns them as an Array"
bound_by_hand "love.sensor.getName",
  reason: "reads its sensor type through luax_checksensortype, an inline helper of wrap_Sensor.cpp that checks " \
    "the name with luax_enumerror, which the parser does not follow"

# love.sound
bound_by_hand "love.sound.newDecoder",
  reason: "chooses among its forms by its argument's kind (luax_cangetfile, luax_istype), where Rice passes " \
    "one C++ type for each argument; Lota binds a filename with its stream type, and Data"
bound_by_hand "love.sound.newSoundData",
  reason: "passes the lua_State to w_newDecoder, which the parser does not read; Lota binds the form with " \
    "numbers and the form with a Decoder, which Lota::Sound::SoundData.new makes from a filename or a FileData " \
    "first, as LÖVE does"
bound_by_hand "Decoder:decode",
  reason: "divides by the 8 bits of a byte, which clang-tidy's readability-magic-numbers refuses; Lota names " \
    "it bits_per_byte"
generate "Decoder:clone"
generate "SoundData:clone"
generate "SoundData:slice"
bound_from_lua "SoundData:getSample",
  note: "divides in double precision, where the C++ wrap function divides in a float"
bound_from_lua "SoundData:setSample",
  note: "multiplies in double precision and stores through LuaJIT's conversions"
bound_from_lua "SoundData:getChannelCount"
bound_from_lua "SoundData:getBitDepth"
bound_from_lua "SoundData:getSampleRate"
bound_from_lua "SoundData:getSampleCount"
bound_from_lua "SoundData:getDuration"
generate "SoundData:copyFrom"
generate "Data:getSize"
bound_by_hand "Data:getString",
  reason: "pushes its bytes with lua_pushlstring from a pointer it computes with a C-style cast and pointer " \
    "arithmetic, which clang-tidy refuses; Lota reads the same bytes through a std::span"
bound_by_hand "Data:performAtomic",
  reason: "calls its function with lua_pcall while it holds the Data's lock; Lota calls the block"
bound_by_hand "Data:getFloat",
  reason: "returns w_Data_getT<float>, a template the parser does not follow, which pushes as many values as " \
    "it is asked for in a loop"
bound_by_hand "Data:getDouble",
  reason: "returns w_Data_getT<double>, as Data:getFloat"
bound_by_hand "Data:getInt8",
  reason: "returns w_Data_getT<int8>, as Data:getFloat"
bound_by_hand "Data:getInt16",
  reason: "returns w_Data_getT<int16>, as Data:getFloat"
bound_by_hand "Data:getInt32",
  reason: "returns w_Data_getT<int32>, as Data:getFloat"
bound_by_hand "Data:getUInt8",
  reason: "returns w_Data_getT<uint8>, as Data:getFloat"
bound_by_hand "Data:getUInt16",
  reason: "returns w_Data_getT<uint16>, as Data:getFloat"
bound_by_hand "Data:getUInt32",
  reason: "returns w_Data_getT<uint32>, as Data:getFloat"
generate "Decoder:getChannelCount"
generate "Decoder:getBitDepth"
generate "Decoder:getSampleRate"
generate "Decoder:getDuration"

# love.system
generate "love.system.setClipboardText"
generate "love.system.getClipboardText"
generate "love.system.getOS"
generate "love.system.getProcessorCount"
generate "love.system.getMemorySize"
generate "love.system.getPowerInfo"
generate "love.system.openURL"
generate "love.system.vibrate"
generate "love.system.hasBackgroundMusic"
bound_by_hand "love.system.getPreferredLocales",
  reason: "builds a table of strings with lua_createtable and lua_rawseti in a loop, which the generator does " \
    "not port; Lota returns the locales as an Array of Strings"

# love.timer
generate "love.timer.step"
generate "love.timer.getDelta"
generate "love.timer.sleep"
generate "love.timer.getFPS"
generate "love.timer.getAverageDelta"
generate "love.timer.getTime"

# love.touch
bound_by_hand "love.touch.getTouches",
  reason: "builds a table of light userdata with lua_createtable and lua_rawseti in a loop, which the generator " \
    "does not port; Lota returns the ids as an Array of Integers"
generate "love.touch.getPosition"
generate "love.touch.getPressure"
generate "love.touch.getDeviceType"
generate "love.touch.isMouse"

# love.window
generate "love.window.getSafeArea"
generate "love.window.getDesktopDimensions"
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
generate "love.window.isHighDPIAllowed"
generate "love.window.getDisplayCount"
generate "love.window.getDisplayName"
generate "love.window.getDisplayOrientation"
generate "love.window.setFullscreen"
generate "love.window.setPosition"
generate "love.window.getPosition"
generate "love.window.setIcon"
generate "love.window.getIcon"
generate "love.window.getVSync"
generate "love.window.setDisplaySleepEnabled"
generate "love.window.isDisplaySleepEnabled"
generate "love.window.hasFocus"
generate "love.window.hasMouseFocus"
generate "love.window.isVisible"
generate "love.window.isOccluded"
generate "love.window.getDPIScale"
generate "love.window.getNativeDPIScale"
generate "love.window.toPixels"
generate "love.window.fromPixels"
generate "love.window.minimize"
generate "love.window.maximize"
generate "love.window.restore"
generate "love.window.focus"
generate "love.window.isMaximized"
generate "love.window.isMinimized"
generate "love.window.requestAttention"
generate "love.window.getSystemTheme"
bound_by_hand "love.window.getFullscreen",
  reason: "raises with luaL_error after it has read the window's settings, which the generator does not port; " \
    "Lota returns the Array (rule 4) and raises love::Exception"
bound_by_hand "love.window.getFullscreenModes",
  reason: "builds a table of tables with lua_createtable, which the generator does not port; Lota returns an " \
    "Array of Arrays, which Lota::Window.fullscreen_modes makes FullscreenModes"
bound_by_hand "love.window.setVSync",
  reason: "reads its argument as a boolean or an integer by its Lua type; Lota::Window.vsync= chooses, and " \
    "binds the integer"
bound_by_hand "love.window.close",
  reason: "marks itself deprecated with luax_markdeprecated, which the generator does not port; " \
    "Lota::Window.close marks it through Lota::Deprecation and binds the call"
bound_by_hand "love.window.showMessageBox",
  reason: "chooses between its forms by whether its third argument is a table, which also holds the " \
    "enterbutton and escapebutton settings; Lota binds each form as a function of its own"
bound_by_hand "love.window.setMode",
  reason: "reads its settings table through readWindowSettings, which Lota::Window.set_mode ports to Ruby"
generate "Font:getHeight"
generate "Font:getLineHeight"
generate "Font:setLineHeight"
generate "Font:getAscent"
generate "Font:getDescent"
generate "Font:getBaseline"
generate "Font:getDPIScale"
generate "Font:setFilter"
generate "Font:getFilter"
bound_by_hand "Font:getWidth",
  reason: "reads its second argument as a string or a number by its Lua type; Lota binds each form as a " \
    "method of its own, which Lota::Graphics::Font#width chooses between"
bound_by_hand "Font:getKerning",
  reason: "reads its arguments as strings or numbers by their Lua type, as Font:getWidth does"
bound_by_hand "Font:hasGlyphs",
  reason: "reads each of its arguments as a string or a number, at positions it computes; Lota binds each " \
    "form, which Lota::Graphics::Font#glyphs? calls for each argument"
bound_by_hand "Font:getWrap",
  reason: "reads colored text through luax_checkcoloredstring and returns its lines as a table it fills in " \
    "a loop"
bound_by_hand "Font:setFallbacks",
  reason: "reads every argument after the first as a Font, at positions it computes; Lota binds an Array " \
    "of them"
generate "love.filesystem.openFile"
generate "File:close"
bound_by_hand "File:getSize",
  reason: "compares the size with the largest integer a double holds exactly, written as a number " \
    "(0x20000000000000LL), which clang-tidy's readability-magic-numbers refuses; Lota names it"
generate "File:open"
generate "File:isOpen"
bound_by_hand "File:read",
  reason: "reads its size at a position it computes (startidx), after a container type it reads only when " \
    "given; Lota reads the container type as a parameter that may be nil"
bound_by_hand "File:write",
  reason: "reads its argument as a string or a Data (lua_isstring, luax_istype); Lota binds each form"
bound_by_hand "File:lines",
  reason: "returns an iterator, a C closure over the File (w_File_lines_i), as love.filesystem.lines; " \
    "Lota binds the iterator's class, which reads from the File and restores its position"
generate "File:flush"
generate "File:isEOF"
bound_by_hand "File:tell",
  reason: "compares the position with the largest integer a double holds exactly, as File:getSize does"
bound_by_hand "File:seek",
  reason: "compares the position with 2^53 written as a number, as File:getSize does, and casts it to " \
    "uint64 with a C-style cast, which clang-tidy's modernize-avoid-c-style-cast refuses"
generate "File:setBuffer"
generate "File:getBuffer"
generate "File:getMode"
generate "File:getFilename"
generate "File:getExtension"
generate "FileData:getFilename"
generate "FileData:getExtension"
bound_by_hand "love.graphics.newImageFont",
  reason: "converts its arguments to a Rasterizer through luax_convobj, reading the stack at the positions it " \
    "computes; Lota::Graphics::ImageFont.new converts the image to an ImageData and binds the Rasterizer " \
    "made from it, with its glyphs, extra spacing, and DPI scale"
bound_by_hand "love.graphics.newTextBatch",
  reason: "reads its text through luax_checkcoloredstring only when it is given; Lota binds the form with " \
    "the text as an Array and the form without it"
bound_by_hand "TextBatch:set",
  reason: "reads its text through luax_checkcoloredstring, which Lota reads as an Array"
bound_by_hand "TextBatch:setf",
  reason: "reads its text through luax_checkcoloredstring, as TextBatch:set, after its wrap limit and " \
    "alignment"
bound_by_hand "TextBatch:add",
  reason: "reads its text through luax_checkcoloredstring and its placement as a Transform or nine numbers; " \
    "Lota binds each form, with the numbers as an Array, as love.graphics.draw"
bound_by_hand "TextBatch:addf",
  reason: "reads its text through luax_checkcoloredstring and its placement as TextBatch:add does"
generate "TextBatch:clear"
generate "TextBatch:setFont"
generate "TextBatch:getFont"
generate "TextBatch:getWidth"
generate "TextBatch:getHeight"
generate "TextBatch:getDimensions"
