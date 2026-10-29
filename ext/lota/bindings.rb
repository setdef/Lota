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
generate "Source:getType"
generate "Source:clone"

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
generate "love.graphics.getFont"
generate "love.graphics.getDefaultFilter"
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
    "generator does not port; Lota binds the targets love.graphics.setCanvas's bound form sets: none or one"
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

# love.keyboard
bound_by_hand "love.keyboard.isDown",
  reason: "reads its keys in a loop over every argument, or from a table; Lota::Keyboard.down? passes them " \
    "as one Array"

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

# love.timer
generate "love.timer.step"
generate "love.timer.getDelta"
generate "love.timer.sleep"

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
bound_by_hand "love.filesystem.openFile",
  reason: "returns luax_ioError's nil and message from a catch block, which the generator does not port; " \
    "Lota returns the File, or the nil and message, as one Array (rule 4)"
generate "File:close"
generate "FileData:getFilename"
