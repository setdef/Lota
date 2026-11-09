<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Lota::Image::ImageData.new` decodes a `Lota::Filesystem::File` or any `Lota::Data`, as `love.image.newImageData` does, and raises `TypeError` for anything else.
- `Lota::Image.new_cube_faces`, returning the six `ImageData` of a cube map in one image, translating `love.image.newCubeFaces`.
- `Lota::Graphics.points` takes an Array of points, each an Array of its x, y, and optionally red, green, blue, and alpha, as `love.graphics.points` takes a table of tables.
- `Lota::Audio.play`, `stop`, and `pause` take several Sources, or an Array of them, as `love.audio.play`, `stop`, and `pause` take several or a table.
- `Lota::Graphics.readback_buffer`, `readback_buffer_async`, `copy_buffer`, `copy_buffer_to_texture`, `copy_texture_to_buffer`, `draw_from_shader`, and `draw_from_shader_indirect`, and `Lota::Graphics::SpriteBatch#attach_attribute`, translating the LÖVE 12 functions of those names.
- `Lota::Physics.new_circle_body`, `new_rectangle_body`, `new_polygon_body`, `new_edge_body`, and `new_chain_body`, each returning a new Body and its Shape.
- LÖVE's deprecated forms of `Lota::Physics::CircleShape.new`, `RectangleShape.new`, `PolygonShape.new`, `EdgeShape.new`, and `ChainShape.new` without a Body, and the deprecated `Lota::Physics::Fixture.new`, which attaches a copy of such a Shape to a Body; `Fixture ===` is true of every Shape.
- `Lota::Data#pointer`, `Lota::Data#ffi_pointer`, and `Lota::Window.pointer`, each a `Fiddle::Pointer` to the address LÖVE gives Lua, the Data's sized as the Data is; they need `gem "fiddle"` in the game's Gemfile, which Lota does not depend on.
- `Lota::Mouse.global_position`, `Lota::Sound::Decoder#seek`, and `Lota::Filesystem.open_native_file`, matching `love.mouse.getGlobalPosition`, `Decoder:seek`, and `love.filesystem.openNativeFile`; `global_position` leaks no memory and places the pointer on its own display, where LÖVE leaks on every call and misplaces it on a third display or after one away from the desktop's origin.
- `Lota::Filesystem.load(name, mode = nil)`, matching `love.filesystem.load`: reads a file of Ruby through LÖVE's filesystem, raises `SyntaxError` at once for code that does not compile, and returns `[proc]`, whose call runs the code at the top level with its arguments as `ARGV`, or `[nil, message]` for a file it cannot read; mode `:b` loads, and `:t` refuses, Ruby's compiled instruction sequences (`RubyVM::InstructionSequence#to_binary`) as LuaJIT's bytecode is binary, and `:b` refuses Ruby source, which is text.
- `Lota::Filesystem::File#open` takes a block: when the file opens, it yields the file, closes it afterward, and returns the block's value; otherwise it returns what `open` returns without a block.
- `Lota::Graphics.stencil_mode=` and `stencil_mode`, `blend_state=` and `blend_state`, `default_mipmap_filter=` and `default_mipmap_filter`, `low_power_preferred?`, and `discard`, translating LÖVE 12's `setStencilMode`, `getStencilMode`, `setBlendState`, `getBlendState`, `setDefaultMipmapFilter`, `getDefaultMipmapFilter`, `isLowPowerPreferred`, and `discard`.
- `Lota::Graphics.clear` takes `false` or `true` in place of the color, and the stencil and depth to clear to, or `false` to leave them, after it.
- `Lota::Graphics.readback_texture_async`, returning a `Lota::Graphics::GraphicsReadback` (`complete?`, `error?`, `wait`, `update`, `buffer_data`, `image_data`).
- `Lota::Graphics::Texture#view_formats`, and `Lota::Graphics::SpriteBatch#add_layer` and `layer=`, translating `SpriteBatch:addLayer` and `setLayer`.
- `Lota::Graphics::CubeTexture.new`, `ArrayTexture.new`, and `VolumeTexture.new`, translating LÖVE 12's `newCubeTexture`, `newArrayTexture`, and `newVolumeTexture`, each returning a `Texture` and matching with `===` a texture of its type; `CubeImage.new` and its kin call them.
- `Lota::Graphics::TextureView.new`, translating `love.graphics.newTextureView` with its settings as keywords and returning a `Texture`; `TextureView === x` is true of every `Texture`.
- `love.video`: `Lota::Video`, which boot opens unless `t.modules.video` is false, and `lota.video`; `Lota::Video::VideoStream` (`new`, `sync=`, `filename`, `play`, `pause`, `seek`, `rewind`, `tell`, `playing?`).
- `Lota::Graphics::Video` (`new` with `audio:` and `dpiscale:`, `stream`, `source`, `source=`, `width`, `height`, `dimensions`, `pixel_width`, `pixel_height`, `pixel_dimensions`, `filter`, `filter=`, `play`, `pause`, `seek`, `rewind`, `tell`, `playing?`), which `Lota::Graphics.draw` draws.
- The gem carries libtheora, which plays Ogg Theora video, under its BSD-3-Clause license, and the notices name it.

### Deprecated

- `Lota::Graphics.canvas_formats` and `image_formats`, returning a frozen `Lota::Graphics::CanvasFormats` and `ImageFormats`; `set_new_font`; `Lota::Graphics::Texture#new_image_data`; and `stencil`, `stencil_test=`, and `stencil_test`, translating the functions LÖVE 12 deprecates, each printing LÖVE's notice the first time it is called.

### Fixed

- `Lota::Audio.recording_devices` returns an empty list when nothing can record, where LÖVE lists one device named `""` that cannot start.
- A finger the system cancels, as iOS does when a gesture takes it, now calls `touchreleased` in order with the other events and leaves `Lota::Touch.touches`; in LÖVE it never ends.
- On Windows, an engine object Lota hands back again, such as the Shader in use or a Shape a contact names, is the same Ruby object each time, as on macOS and Linux, where it was a new one each time.
- On Vulkan, `Lota::Graphics.present` no longer raises `IndexError` ("vector") when a rebuilt swap chain has more images than the first, as on Android with vsync off; LÖVE's `vulkan/Graphics.cpp` is now compiled with Lota's patch `ext/lota/engine/vulkan_semaphores.patch` on Linux, Windows, and Android.
- On Vulkan, a present that fails before its frame reaches the GPU leaves the error screen able to draw, where it crashed; LÖVE's `vulkan/Graphics.cpp` is also compiled with Lota's patch `ext/lota/engine/vulkan_submit.patch`.
- A game whose audio device goes away, as when headphones are unplugged, keeps running: Lota calls `Lota.audiodisconnected(sources)` with the Sources that stopped and, unless it returns a truthy value, moves playback to the system's default device, as LÖVE does; before, the event raised an error.

## [0.3.1] - 2026-11-09

### Added

- `lota fuse --sign-command COMMAND` and `--notarize PROFILE` pass Fledge's options of the same names, signing a Windows app with a command of your own and having Apple notarize a signed macOS app, and `Lota::Fuse::Options#sign_command` and `#notarize` hold them.
- `love.image`'s compressed images: `Lota::Image::CompressedData.new` reads a DDS, KTX, PVR, PKM, or ASTC file into a `Lota::Image::CompressedImageData` (`clone`, `width`, `height`, `dimensions`, `mipmap_count`, `format`, `linear=`, `linear?`), and `Lota::Image.compressed?` asks whether it can; `Lota::Graphics::Texture.new` and `Image.new` also take a CompressedImageData.

### Changed

- `lota fuse` builds with Fledge 0.10.0, was 0.9.0.

### Fixed

- On iOS 27 and iPadOS 27, a game launched in landscape gets a landscape window, where SDL gave it a portrait one, cut off at the bottom and black on the right: the iOS host reports the window scene's orientation where UIKit's `statusBarOrientation` no longer does.

## [0.3.0] - 2026-11-08

### Added

- `lota fuse --exclude PATTERN`, repeatable, leaves paths out of the app, and `Lota::Fuse::Options#exclude` holds the patterns.
- `rake ios:notices[PROJECT]` and `rake android:notices[PROJECT]` write a phone project's `NOTICES.txt`, and on Android copy OpenAL Soft's source into its `sources/` folder.
- The rest of `love.math`: `Lota::Math::BezierCurve` and every method of it, `Lota::Math::RandomGenerator` (`new`, `random`, `random_normal`, `seed`, `seed=`, `state`, `state=`), and `Lota::Math.random_normal`, `random_seed`, `random_state`, `random_state=`, `color_to_bytes`, `color_from_bytes`, `gamma_to_linear`, `linear_to_gamma`, `convex?`, `triangulate`, `perlin_noise`, `simplex_noise`, and the deprecated `noise`.
- `love.data`: `Lota::Data.compress`, `decompress`, `encode`, `decode`, `hash` (with no arguments still Ruby's `Object#hash`), `pack`, `unpack`, and `packed_size`, whose container `:data` returns a plain `Lota::Data`, as LÖVE returns a plain Data, and `Lota::Data::ByteData` (with `string=` and the writers of numbers, `float=` to `uint32=`), `Lota::Data::CompressedData` (with `format`), and `Lota::Data::DataView`.
- Every engine object has LÖVE's `release`, and its `__tostring` and `__eq` as `to_s` (`"Texture: 0x0127c3a4f0"`) and `==`.
- The gem carries Noise1234, which the noise functions link, under its public-domain dedication, and the notices name it.
- `love.font`: `Lota::Font::Rasterizer` (`new`, `height`, `advance`, `ascent`, `descent`, `line_height`, `glyph_data`, `glyph_count`, `glyphs?`), `Lota::Font::GlyphData` (`new`, `clone`, `width`, `height`, `dimensions`, `glyph`, `glyph_string`, `advance`, `bearing`, `bounding_box`, `format`), and `Lota::Font::TrueTypeRasterizer.new`, `BMFontRasterizer.new`, and `ImageRasterizer.new`; `Lota::Graphics::Font.new` and `ImageFont.new` also take a Rasterizer.

### Changed

- Apps' notices now name setdef as Lota's copyright holder.
- `lota fuse` builds with Fledge 0.9.0, was 0.6.0.
- **Breaking:** `Lota::Object` and `Lota::Data` are classes, LÖVE's root types: every engine object's class inherits from `Lota::Object`, and every Data's from `Lota::Data`, where they included them as modules. Neither has `new`, as LÖVE makes neither.
- **Breaking:** `Lota::Sensor.get_name` is `Lota::Sensor.name`, by rule 3; with no sensor type it is Ruby's `Module#name`.
- **Breaking:** what Lota's classes use to reach each other is no longer public: every engine object's `native`, every class's `from_native`, and helpers such as `Lota::Graphics.colored_text`, `Lota::Physics.shape`, and `Lota::Font.file_data`.
- `type_of?` takes a type's name as a Symbol (`texture.type_of?(:Drawable)`), and still as a String.

### Fixed

- `Lota::Event.restart` starts the game again under `bundle exec lota run`, where it ran `bundle` again and failed (`Could not find command "run"`).
- A game `lota fuse` built restarts, as a fused LÖVE game does, where it quit: its app's program runs again with the same arguments, and `Lota.restart` holds the value.
- `Lota::Graphics::Font.new(size, nil, dpiscale)` and `Font.new(data, size, nil, dpiscale)` ignore the DPI scale after a `nil` hinting mode, as LÖVE does, rather than using it.
- The phone and Windows builds' downloads retry a failed connection.
- A File `Lota::Filesystem.open_file` opens is closed once it is released or collected; it stayed open until the program ended, as Lota kept a reference to it of its own.
- `Lota::Graphics::Font.new`'s size, `Lota::Graphics::ImageFont.new`'s extra spacing, and `Lota::Graphics.stencil_state=`'s value take a Float and cut it toward 0, as LÖVE reads them, where they raised `TypeError`.
- `lota fuse` installs none of the game's gems: Bundler only locks them, and Fledge, which runs from a Gemfile of its own in `dist/fuse-tools`, compiles only the gems the app ships, so a gem with a C extension in the `development` or `test` group no longer compiles, or fails a build. A failed build of a game with gems now says what a compiler needs.
- `lota fuse` run under `bundle exec` no longer fails to lock: the Bundler commands it runs drop the setup of the bundle it runs in, which `bundle exec` names in `RUBYOPT` by its full path.
- On Android, a game keeps running when dark mode, the font's size or weight, the language, or the system's overlays change (as a new wallpaper's colours change them on Android 12 and later), and hears dark mode as `Lota.themechanged` and the language as `Lota.localechanged`; before, Android restarted the activity and SDL closed the app.
- On Android, a game keeps running when the display size (density) changes, and keeps the scale it launched with; before, Android restarted the activity and SDL closed the app.
- On Android, a game on Vulkan no longer crashes when it leaves the screen (Home, another app, the screen turned off, or a share sheet): the host waits for the game to pause before SDL releases its window, and the game stops while hidden and draws again when it returns.

## [0.2.2] - 2026-11-06

### Changed

- `lota fuse` builds with Fledge 0.6.0, was 0.5.1.

### Fixed

- A release's Windows gems are delivered again: the license record no longer reads LÖVE's version file, which the jobs that deliver a gem do not check out. The tag v0.2.1 was pushed and published nothing for this.

## [0.2.1] - 2026-11-06

### Added

- `Lota::Filesystem.append`, `directory_items`, `real_directory`, `exists`, `mount` (of a path, a `Lota::Data`, or a `FileData`) and `unmount`, `mount_full_path` and `unmount_full_path`, `mount_common_path` and `unmount_common_path`, `full_common_path`, `source`, `source_base_directory`, `working_directory`, `user_directory`, `appdata_directory`, `executable_path`, `canonicalize_real_path`, `symlinks_enabled?` and `symlinks_enabled=`, and `require_path` and `c_require_path` and their writers, which Ruby's `require` does not read.
- Every method of `Lota::Filesystem::File`: `open`, `open?`, `mode`, `filename`, `extension`, `size`, `read` (into a String or a `FileData`), `write`, `flush`, `eof?`, `tell`, `seek`, `set_buffer`, `buffer`, and `lines`; and `FileData#extension`.
- `Lota::Audio.pause`, `set_effect` (its settings as keywords) and `effect` (a frozen `Lota::Audio::Effect`), `active_effects`, `max_scene_effects`, `max_source_effects`, `effects_supported?`, `set_mix_with_system`, `playback_device`, `playback_devices`, `set_playback_device`, `recording_devices`, `set_output_spatialization`, `output_spatialization`, and `output_spatialization_filters`.
- `Lota::Audio::QueueableSource.new`, translating `love.audio.newQueueableSource` and returning a `Source`, whose `===` asks for a Source of the type `:queue`; and `Source#queue`, `set_filter` and `filter` (a frozen `Lota::Audio::Filter`), `set_effect`, `effect`, and `active_effects`.
- `Lota::Audio::RecordingDevice`, with `start`, `stop`, `data`, `sample_count`, `sample_rate`, `bit_depth`, `channel_count`, `name`, and `recording?`.
- Boot passes `t.audio.mixwithsystem` and `t.audio.mic` to the engine before the audio module opens, and sets the window's icon from `t.window.icon`, as LÖVE's boot does.
- `Lota::Mouse.cursor`, translating `love.mouse.getCursor`, and `Lota::Mouse::Cursor.new`, translating `love.mouse.newCursor`, of an image or an Array of them.
- Experimental: under Fledge's `fledge build android`, the source gem builds LÖVE's engine and the extension for Android's arm64-v8a and x86_64 into the app's `libfledgeext.so`, from a clone of Lota named with `--with-lota-source`, LÖVE's dependencies, SDL 3.4.10 among them, built by `rake android:deps` (`--with-lota-android-deps`), and Rice (`--with-rice-dir`); SDL and OpenAL Soft ship beside it as `libSDL3.so` and `libopenal.so`, the latter with its OpenSL ES backend.
- Phone hosts in the gem, `ext/lota/phone/host/ios` and `ext/lota/phone/host/android`, which a game's Fledge project copies and names under `ios: host:` and `android: host:`: SDL's startup files, SDL 3.4.10's Java classes, the Android Activity methods LÖVE's engine calls, and an opt-in for a game to handle Android's Back itself.
- `lota fuse` writes `app/NOTICES.txt` into every app: Lota's license, each library the platform's gem carries with its version, licenses, and notices of copyright, FreeType's credit, where OpenAL Soft's source archive is in the app, and the text of each license.
- Each precompiled gem carries `notices.json`, the manifest of what it carries, from which `lota fuse` writes those notices.

### Changed

- `lota fuse` stops on a Lota gem without `notices.json`, as every gem built before this release is.

### Fixed

- On Android, a game that draws with Vulkan, LÖVE's first choice there, runs in landscape as it does in portrait: LÖVE rebuilt its swap chain on every frame while the phone was turned, which took 60 frames a second down to 20 or 30.

## [0.2.0] - 2026-11-05

### Added

- `Lota::Physics::MouseJoint#target=` and `#target`, `#max_force=` and `#max_force`, `#stiffness=` and `#stiffness`, and `#damping=` and `#damping`, so a game can move a mouse joint.
- `Lota::Physics::Body#awake=`, `#active=`, `#transform` and `#transform=`, `#kinematic_state` and `#kinematic_state=`, `#angular_velocity=`, `#angular_damping=`, `#inertia=`, `#local_vector`, `#linear_velocity_from_world_point`, `#linear_velocity_from_local_point`, and the deprecated `#fixtures`.
- `Lota::Physics::Shape#filter_data=` and the deprecated `#shape`; `CircleShape#radius=`, `#point`, and `#point=`; `PolygonShape#points` and `#validate`; `EdgeShape#points`, `#next_vertex`, and `#previous_vertex` and their writers; `ChainShape#points`, `#point`, `#vertex_count`, `#next_vertex`, and `#previous_vertex` and their writers, and the deprecated `#child_edge`.
- `Lota::Physics::Contact#tangent_speed` and `#tangent_speed=`, `#destroyed?`, and the deprecated `#fixtures`; the deprecated `World#query_bounding_box`.
- Every method of `DistanceJoint`, `FrictionJoint`, `GearJoint`, `MotorJoint`, `PrismaticJoint`, `PulleyJoint`, `RevoluteJoint`, `RopeJoint`, `WeldJoint`, and `WheelJoint` in `Lota::Physics`: their lengths, limits, motors, springs, offsets, axes, anchors, ratios, and reference angles.
- `Lota::Physics.compute_linear_stiffness`, `compute_linear_frequency`, `compute_angular_stiffness`, and `compute_angular_frequency`.
- `lota fuse` ships the gems a game's `Gemfile.lock` locks, at those versions: pure Ruby, from Git, from the game's `vendor/cache`, and with C extensions, which compile on the building computer.

### Changed

- `lota fuse` builds with Fledge 0.5.1, was 0.5.0.
- Breaking: `lota fuse` refuses a game whose Gemfile has no `Gemfile.lock`, whose lockfile does not lock the platform it builds for, or whose lockfile locks another version of Lota; it fused a game with a Gemfile before, without the Gemfile's gems, and warned.

### Fixed

- A game keeps drawing while the system holds its window in a loop of its own, as Windows does while the player drags or resizes it: `Lota::Boot` hands each new frame to the event module's modal draw, as LÖVE's boot does, unless the game set `Lota::Event.modal_draw_callback=`.

## [0.1.3] - 2026-11-05

### Added

- `lota fuse [path]`, which builds a game folder with Fledge into an app for this computer's platform that runs without Ruby, with `--out`, `--identifier`, `--app-version`, `--icon`, and `--sign`; `Lota::Boot#read_settings` and `Lota::Boot.folder_identity`, which it reads a game's name and identity with.
- Experimental: under Fledge's `fledge build ios`, the source gem builds LÖVE's engine and the extension as static archives for the iOS device and Simulator, from a clone of Lota named with `--with-lota-source`, SDL3 built by `rake ios:sdl3` (`--with-lota-sdl3`), and Rice (`--with-rice-dir`); audio uses Apple's OpenAL framework there, as LÖVE's iOS build does.
- `Lota::Touch`, translating `love.touch`: `touches` (the ids of the fingers down, as Integers, optionally of one device type), `position`, `pressure`, `device_type`, and `mouse?`; boot opens it unless `t.modules.touch = false`, and `lota.touch` returns it.
- `Lota::Joystick`, translating `love.joystick`: `joysticks`, `joystick_count`, `background_events=` and `background_events?`, and the gamepad mapping database's `set_gamepad_mapping`, `load_gamepad_mappings`, `save_gamepad_mappings`, and `gamepad_mapping_string`; boot opens it unless `t.modules.joystick = false`, and `lota.joystick` returns it.
- `Lota::Joystick::Joystick`, LÖVE's `Joystick`, with every method of `wrap_Joystick.cpp`, its gamepad's buttons, axes, mappings, vibration, player index, and sensors among them. The joystick and gamepad callbacks (`joystickadded`, `joystickremoved`, `joystickpressed`, `joystickreleased`, `joystickaxis`, `joystickhat`, `gamepadpressed`, `gamepadreleased`, `gamepadaxis`, `joysticksensorupdated`) receive it, the same object each time.
- `Lota::Sensor`, translating `love.sensor`: `sensor?`, `enabled?`, `enabled=` (of a type and a setting), `data`, and `get_name`, which keeps LÖVE's prefix while rule 3's `name` would replace `Module#name`; boot opens it unless `t.modules.sensor = false`, and `lota.sensor` returns it.

### Fixed

- An engine object read back that a game had kept no reference to, such as each of `World#bodies` or `Body#shapes` read every frame, no longer comes back as the wrapper Ruby's garbage collector had already found dead, which the collector then freed while the game used it and crashed it.
- A `TextBatch` freed by Ruby's garbage collector on another thread is released on the main thread, as every other `love.graphics` object is; it was released where it was freed.
- The error screen stops every joystick's vibration and all audio, as LÖVE's does.
- The `aarch64-mingw-ucrt` gem renders with OpenGL as well as Vulkan; its SDL was built without OpenGL.

## [0.1.2] - 2026-11-04

### Added

- Precompiled gems for Windows with RubyInstaller's Ruby, `x64-mingw-ucrt` and `aarch64-mingw-ucrt`, which carry `OpenAL32.dll` and its source beside the extension and link every other library of LÖVE's into it.
- `Lota::Graphics::GraphicsBuffer`, LÖVE's `GraphicsBuffer`, and `Lota::Graphics::Buffer`, a module whose `new` translates `love.graphics.newBuffer` and returns one, with its format (a Symbol or an Array of Hashes, or `GraphicsBuffer::Format` records), its content (a count, an Array of numbers or of Arrays, or a `Lota::Data`), `vertex:`, `index:`, `texel:`, `shaderstorage:`, and `indirectarguments:`, `usage:`, and `debugname:`; and `GraphicsBuffer#set_array_data`, `clear`, `element_count`, `element_stride`, `size`, `format`, `buffer_type?`, and `debug_name`.
- `Lota::Graphics::Mesh.new`, translating `love.graphics.newMesh` in its three forms (standard vertices, a vertex format of your own, and attributes of buffers), with `set_vertices`, `vertex=` and `vertex`, `vertex_attribute=` and `vertex_attribute`, `vertex_count`, `vertex_format` (`Mesh::VertexFormat` records), `attribute_enabled=` and `attribute_enabled?`, `attach_attribute`, `detach_attribute`, and `attached_attributes` (an empty Array, as LÖVE's function returns an empty table), `vertex_buffer`, `flush`, `set_vertex_map` and `vertex_map`, `index_buffer=` and `index_buffer`, `texture=` and `texture`, `draw_mode=` and `draw_mode`, and `draw_range=` and `draw_range`. A vertex format of arrays, and a vertex format that names its attributes and gives no location, print LÖVE's deprecation notices.
- `Lota::Graphics::ParticleSystem.new`, translating `love.graphics.newParticleSystem`, with every method of `ParticleSystem` (its writers and getters, `colors=`, `sizes=`, `quads=`, `emission_area=`, and the ranges, which take one number or two), `start`, `stop`, `pause`, `reset`, `emit`, `update`, `active?`, `paused?`, `stopped?`, `count`, `move_to`, and `clone`.
- `Lota::Graphics::ComputeShader.new`, translating `love.graphics.newComputeShader` and returning a `Shader`; `ComputeShader === shader` asks `shader.stage?(:compute)`.
- `Lota::Graphics.draw` draws a `Mesh` or a `ParticleSystem`, placed by numbers or a `Lota::Math::Transform`; `Lota::Graphics.draw_instanced`, `draw_indirect`, `dispatch_threadgroups`, `dispatch_indirect`, and `quad_index_buffer`, translating `drawInstanced`, `drawIndirect`, `dispatchThreadgroups`, `dispatchIndirect`, and `getQuadIndexBuffer`.
- `Shader#send` takes a `GraphicsBuffer` for a texel or storage buffer uniform, and `Shader#buffer_format` returns the members of a buffer a shader declares as `Shader::BufferFormat` records.

### Changed

- LÖVE's `Mesh.cpp` is now compiled with a second patch of Lota's (`ext/lota/engine/mesh.patch`), which frees a Mesh's vertex data with `delete[]`, as it was allocated, where LÖVE's frees it with `delete`.

## [0.1.1] - 2026-11-03

### Fixed

- The `x86_64-linux-gnu` gem's libvorbis no longer needs glibc's `libmvec.so.1`, which the manylinux policy does not allow, so every library the Linux gems carry needs only glibc's and GCC's C++ runtime libraries that it allows.
- The `arm64-darwin` gem's frameworks keep only rpaths inside the gem, so a framework installed in `/Library/Frameworks` can no longer shadow the gem's `ogg.framework`.

## [0.1.0] - 2026-11-03

### Changed

- **Breaking:** `Lota::Graphics.canvas` returns an Array, as every function that can return several values does: `[]` while drawing goes to the window, the canvases set, or one Array of the targets and their options where LÖVE returns its table; take `.first` for the one canvas.

### Added

- `Lota::Native`, the compiled extension that binds LÖVE's engine, with `Lota::Native::RandomGenerator`.
- `Lota::Graphics::Canvas.new`, `Lota::Graphics.canvas=`, `Lota::Graphics.clear`, and `Lota::Graphics.readback_texture`, translating `love.graphics.newCanvas`, `setCanvas`, `clear`, and `readbackTexture`.
- `Lota::Graphics::Texture`, with `canvas?`; `Canvas.new` returns a `Texture`, as LÖVE 12's `newCanvas` does, and `Canvas === texture` asks `texture.canvas?`.
- `Lota::Graphics::Texture.new`, translating `love.graphics.newTexture` for an image from a file name, a `FileData`, or an `ImageData`, an Array of mipmaps, or a size with no pixels.
- `Lota::Graphics::Image.new`, translating `love.graphics.newImage`, which in LÖVE 12 is `newTexture`; `Image === x` is true for any `Texture`, canvases included.
- LÖVE's error messages name Lota's modules and methods (`Lota::Image`, `Lota::Window.set_mode`, `Lota::Image::ImageData#pixel`) where LÖVE's name Lua's (`love.image`, `love.window.setMode`, `ImageData:getPixel`), each method by the exact name ADR 001's rules give it.
- `Lota::Image::ImageData`, decoded from a `Lota::Filesystem::FileData` or a file name, with `width`, `height`, and `pixel`.
- `Lota::Filesystem::FileData.new(contents, name)`, translating `love.filesystem.newFileData`.
- `Lota::Graphics` raises `ThreadError` anywhere but the main thread, as LÖVE keeps `love.graphics` there.
- Graphics objects that Ruby's garbage collector frees on another thread are released on the main thread.
- Dependency on SDL3, FreeType, and HarfBuzz, from `love-apple-dependencies`, which `Lota::Native` now loads at run time.
- A precompiled gem for Apple Silicon macOS (platform `arm64-darwin`) and Ruby 4.0, carrying the compiled extension and the frameworks it loads, with their licenses recorded by the REUSE Specification (`REUSE.toml`, and the texts in `LICENSES/`), so `gem install lota` compiles nothing.
- Precompiled gems for Linux with glibc 2.35 or newer on x86_64 and arm64 (platforms `x86_64-linux-gnu` and `aarch64-linux-gnu`) and Ruby 4.0, carrying the compiled extension and the shared libraries it loads, built from source as LÖVE's own Linux CI builds them (SDL 3.4.10, FreeType 2.13.3 with bzip2 1.0.8, HarfBuzz 10.1.0, OpenAL Soft 1.24.3 with its source, libmodplug 0.8.8.5, libvorbis 1.3.7, libogg 1.3.5, and zlib 1.3), with their licenses recorded as the macOS gem's are; RubyGems picks the source gem on musl, such as Alpine Linux.
- On Linux, a game that is not fused saves in `$XDG_DATA_HOME/lota/<identity>`, or `~/.local/share/lota/<identity>`, where LÖVE's `love` saves in a `love` folder.
- The gem's homepage, source code, and changelog links, pointing at https://github.com/setdef/lota.
- The source gem stops at `gem install` with a message naming the precompiled gem, since it ships no LÖVE sources to build from.
- The `lota` executable: `lota run [path] [arguments]` runs the game in a folder, as `love path/to/game` does.
- A game is a folder of `conf.rb` and `main.rb`; `Lota::Boot` starts it in `boot.lua`'s order, calling `def Lota.conf(t)` with a `Lota::Settings` under LÖVE's names and defaults, which accepts and ignores settings LÖVE does not know and reads a setting never set as `nil`; `lota run` puts the folder on `$LOAD_PATH` and leaves the working directory alone.
- `Lota.run`, the game loop translated from `love.run`, calls the callbacks a game defines on `Lota` (`load`, `update`, `draw`, `quit`, `keypressed`, and the rest of LÖVE's), passing each only the arguments it declares and `nil` for a required parameter beyond LÖVE's (an optional one keeps its default), with Integers for the numbers LÖVE holds as integers (a mouse button, a resized window's size) and Floats for the rest; a game can define its own `Lota.run`.
- A private `Kernel#lota` returning `Lota`, and `Lota.filesystem`, `image`, `graphics`, `timer`, `event`, and `window` returning their modules, or `nil` when a module is not open, as when the settings turn it off.
- `Lota::Window.set_mode`, `title=`, and `title`, translating `love.window.setMode`, `setTitle`, and `getTitle`.
- `Lota::Timer.step` and `sleep`, and `Lota::Event.pump` and `quit`, translating `love.timer` and `love.event`; a quit's exit status leaves the event queue as an Integer, so `Lota::Event.quit(3)` exits with 3.
- `Lota::Event.restart` restarts the game, as `love.event.restart` does: `lota run` ends the game as a quit does, then runs itself again with `exec` (same process id, command, and arguments), and `Lota.restart`, for `love.restart`, holds the first value passed to `restart` (`nil`, a boolean, a Float, a String, or a table, as an Array or a Hash; `nil` on a normal start). A game that restarts every time it starts never ends, as in LÖVE.
- `Lota::Graphics.active?`, `origin`, `background_color`, `present`, `width`, `height`, and `dimensions`.
- `Lota::Graphics.rectangle`, `circle`, `ellipse`, `arc`, and `line`, translating `love.graphics.rectangle` (with rounded corners), `circle`, `ellipse`, `arc` (with its `:pie`, `:open`, or `:closed` arc mode), and `line`, in `:fill` or `:line` mode.
- `Lota::Graphics.draw`, translating `love.graphics.draw` for a `Texture`, a `Texture` through a `Quad`, or a `SpriteBatch`, with a position, angle, scale, origin, and shear.
- `Lota::Graphics::Quad.new`, translating `love.graphics.newQuad` with a texture or its size and an optional layer, with `viewport`, `viewport=`, `texture_dimensions`, `layer`, and `layer=`.
- `Lota::Graphics::SpriteBatch.new`, translating `love.graphics.newSpriteBatch` with its size and usage hint, with `add`, `set`, `clear`, `flush`, `texture`, `texture=`, `color`, `color=`, `count`, `buffer_size`, `draw_range`, and `draw_range=` (`nil` draws every sprite again); `draw_range` is `[]` while every sprite is drawn, as every function with several results returns an Array of all it returns.
- `Lota::Graphics::Texture#width`, `#height`, and `#dimensions`, translating `Texture:getWidth`, `getHeight`, and `getDimensions`, of the first mipmap or the one given; and `#render_to`, translating `Texture:renderTo`, whose function becomes a block, putting back the canvas set before even when the block raises.
- `lota run` checks `t.version` as `boot.lua` does: a version the engine is not compatible with prints LÖVE's warning and shows it in a dialog before the window opens.
- `Lota::Graphics.color=` and `color`, `line_width=` and `line_width`, and `line_style=` and `line_style`, translating `love.graphics.setColor`, `getColor`, `setLineWidth`, `getLineWidth`, `setLineStyle`, and `getLineStyle`.
- `Lota::Keyboard.down?`, translating `love.keyboard.isDown`, and `Lota.keyboard` returning `Lota::Keyboard`.
- `Lota::Graphics.print` and `printf`, translating `love.graphics.print` and `printf`, which draw a String or colored text with a position, angle, scale, origin, and shear, `printf` wrapped at a limit and aligned `:left`, `:center`, `:right`, or `:justify`, in the current font or a `Font` given before the position.
- `Lota::Graphics::Font.new`, translating `love.graphics.newFont` for LÖVE's default font at a size and for a TrueType font in a file or a `Lota::Filesystem::FileData`, with its hinting and DPI scale after the size or as keywords; and `Lota::Graphics.font=` and `font`, translating `setFont` and `getFont`, which until set is LÖVE's default font, Noto Sans at 13 pixels.
- `Lota::Graphics.default_filter=` and `default_filter`, translating `love.graphics.setDefaultFilter` and `getDefaultFilter`.
- `lota run` opens LÖVE's font module unless `t.modules.font = false`, as `boot.lua` opens `love.font`.
- `lota run` opens LÖVE's filesystem with the game's folder as its source, as `boot.lua` does, so a file name a game passes is read from its folder, and names its save directory after the folder, then after `t.identity` (with `t.appendidentity`).
- A game saves in the system's application data folder (on macOS, `~/Library/Application Support`), in a `Lota` folder under its identity, where LÖVE's saves in a `LOVE` one; a fused game, which `Lota::Boot.new(path, fused: true)` starts, saves under its identity alone, where LÖVE's fused game does.
- `Lota::Filesystem.identity=`, `identity`, `save_directory`, `fused?`, `fused=`, `create_directory`, `remove`, and `lines`, translating `love.filesystem.setIdentity`, `getIdentity`, `getSaveDirectory`, `isFused`, `setFused`, `createDirectory`, `remove`, and `lines`, whose iterator becomes an Enumerator.
- `Lota::Audio::Source.new`, translating `love.audio.newSource` with a file name or a `FileData` and `:static` or `:stream`, a `Lota::Sound::SoundData`, or a `Lota::Sound::Decoder`, with `play`, `stop`, `pause`, `playing?`, `pitch`, `pitch=`, `volume`, `volume=`, `looping?`, `looping=`, `channel_count`, and `get_type`; `Lota::Audio.play`, `stop`, `volume`, `volume=`, and `active_source_count`; and `Lota.audio` and `Lota.sound`, opened unless the settings turn them off, falling back to LÖVE's silent audio module, as LÖVE does, when OpenAL cannot open a device.
- `Lota::Mouse.y`, `position`, `x=`, `y=`, `position=`, and `down?`, translating `love.mouse.getY`, `getPosition`, `setX`, `setY`, `setPosition`, and `isDown`; and `Lota::Timer.delta`, translating `love.timer.getDelta`.
- Dependency on libvorbis, libogg, and libmodplug, from `love-apple-dependencies`, which the precompiled gem now carries, and on OpenAL Soft 1.24.3, which the precompiled gem carries as a framework of its own, a player can replace, with the release's source archive in `sources/` and its licenses recorded, as its license, the GNU Library General Public License, asks.
- `Lota::Mouse.system_cursor`, `cursor=`, and `x`, translating `love.mouse.getSystemCursor`, `setCursor`, and `getX`, with `Lota::Mouse::Cursor` and its `get_type`; and `Lota.mouse`, opened unless `t.modules.mouse = false`.
- `Lota::Math.random` and `random_seed=`, translating `love.math.random` and `setRandomSeed`, which draw from LÖVE's own generator; and `Lota.math`, opened unless `t.modules.math = false`.
- `Lota::Event.poll`, translating `love.event.poll`, as an Enumerator of each queued message's name and arguments that also takes a block; and `Lota::Event.push` and `clear`.
- `Lota::Object`, included by every engine object (`Texture`, `Font`, `ImageData`, `FileData`, `Cursor`), with `object_type` and `type_of?`, translating `Object:type` and `Object:typeOf`, with LÖVE's type names and parents, and `type`, another name for `object_type`, on every class but those with LÖVE's `getType` (`Body`, `Shape`, `Joint`, `Source`, and `Cursor`), which answer `get_type` and have no `type` or `type=`.
- `Lota::Font` and `Lota.font`, for LÖVE's font module, `nil` when `t.modules.font = false`.
- `Lota::System.clipboard_text=` and `clipboard_text`, translating `love.system.setClipboardText` and `getClipboardText`, and `Lota.system`; `lota run` opens the system module before `conf.rb`, as `boot.lua` does.
- LÖVE's error screen: an error a game raises prints the error and its Ruby backtrace and shows them in the game's window, as `love.errorhandler` does, until the player presses Escape or quits; Ctrl+C copies them. A game may define `Lota.errorhandler` to replace it; `Lota.errhand` is another name for the default handler.
- `Lota::Filesystem.info`, `read`, and `write`, translating `love.filesystem.getInfo`, `read`, and `write`: `info` returns a frozen `Lota::Filesystem::Info` with LÖVE's fields (`type`, `readonly`, `size`, `modtime`) or `nil`, and takes LÖVE's file type filter; `read` returns `[contents, size]`, and `write` `[true]`, or either `[nil, message]` when the file cannot be read or written.
- `Lota::Graphics.push`, which also takes a block and pops after it, `pop`, `translate`, `scale`, and `shear`, translating `love.graphics.push`, `pop`, `translate`, `scale`, and `shear`.
- `Lota::Graphics.background_color=`, `blend_mode=` and `blend_mode`, `canvas`, `color_mask=` and `color_mask`, `depth_mode=` and `depth_mode`, `front_face_winding=` and `front_face_winding`, `line_join=` and `line_join`, `mesh_cull_mode=` and `mesh_cull_mode`, `point_size=` and `point_size`, `scissor=` and `scissor`, `intersect_scissor`, `stack_depth`, `stencil_state=` and `stencil_state`, `gamma_correct?`, `wireframe=` and `wireframe?`, and `renderer_info`, translating LÖVE's drawing state; `scissor = nil`, `depth_mode = nil`, `stencil_state = nil`, and `color_mask = nil` reset them as the setters with no arguments do.
- `Lota::Graphics.points` and `polygon`, translating `love.graphics.points` (without colored points) and `polygon`, with coordinates as numbers or one Array.
- `Lota::Math::Transform`, translating `love.math.newTransform` and Transform's methods, `isAffine2DTransform` as `affine2d_transform?` and `__mul` as `*`; `clone` and `dup` make LÖVE's copy, `transformation=` and `matrix=` are writers, and `translate`, `rotate`, `scale`, `shear`, `reset`, `apply`, and `inverse_of` return the Transform.
- `Lota::Graphics.rotate`, `apply_transform`, `replace_transform`, `transform_point`, `inverse_transform_point`, `projection=`, and `reset_projection`, and `Lota::Graphics.push`'s Transform after the stack type.
- `Lota::Graphics.dpi_scale`, `pixel_width`, `pixel_height`, `pixel_dimensions`, and `flush_batch`, translating `love.graphics.getDPIScale`, `getPixelWidth`, `getPixelHeight`, `getPixelDimensions`, and `flushBatch`.
- `Lota::Graphics.stats`, `supported`, `system_limits`, `texture_formats`, and `texture_types`, translating `love.graphics.getStats`, `getSupported`, `getSystemLimits`, `getTextureFormats` (its settings as keywords), and `getTextureTypes`, each a frozen record with LÖVE's field names.
- `Lota::Record`: every record Lota returns (`Lota::Filesystem::Info`, `Lota::Window::Mode`, and the graphics queries) answers `[]` with a field's name, as a Lua table answers brackets, so `texture_types["2d"]` reads a field no method can name.
- `Lota::Graphics.capture_screenshot`, translating `love.graphics.captureScreenshot` with a block or anything that answers `call`, which receives the next frame as an `ImageData`, or a file name, which saves it in the save directory.
- `Lota::Graphics::Font#height`, `width`, `wrap`, `line_height` and `line_height=`, `filter` and `filter=`, `ascent`, `descent`, `baseline`, `glyphs?`, `kerning`, `fallbacks=`, and `dpi_scale`, translating Font's metrics, with a glyph's code point wherever LÖVE takes one.
- LÖVE 12's deprecated window settings work as in LÖVE: `t.window.highdpi` allows high DPI before the window opens, `t.window.display` chooses the display, and a number for `t.window.depth` is whether it is not zero; `Lota::Window.set_mode` and `update_mode` take them as `highdpi:`, `display:`, and `depth:`, and the first use of each prints LÖVE's deprecation notice, unless the game is fused, through `Lota::Deprecation`.
- `Lota::Window.high_dpi_allowed?`, translating `love.window.isHighDPIAllowed`.
- `Lota::Image::ImageData#encode`, translating `ImageData:encode`, which returns a `Lota::Filesystem::FileData` in `:png`, `:tga`, `:exr`, or another format LÖVE encodes, and with a file name also writes it to the save directory; with `Lota::Graphics.capture_screenshot`, a game saves a frame without Ruby touching its pixels.
- `Lota::Image::ImageData#dimensions`, `format`, `paste`, `linear?`, and `linear=`, and `Lota::Filesystem::FileData#filename`.
- `Lota::Filesystem.open_file`, translating `love.filesystem.openFile`, which returns `[file]` or `[nil, message]`, and `Lota::Filesystem::File`, with `close`.
- LÖVE's texture settings as keywords on `Texture.new`, `Image.new`, and `Canvas.new` (`mipmaps:`, `mipmapcount:`, `format:`, `linear:`, `msaa:`, `dpiscale:`, `readable:`, `canvas:`, `computewrite:`, `viewformats:`, `debugname:`, and, given a size, `type:`, `width:`, `height:`, and `layers:`), with LÖVE's errors for a setting or value it does not know; `Canvas.new` also takes a layer count, or its size as keywords alone.
- `Lota::Graphics::ArrayImage.new`, `CubeImage.new`, and `VolumeImage.new`, translating `love.graphics.newArrayImage`, `newCubeImage`, and `newVolumeImage`, each returning a `Texture` and matching with `===` a texture of its type.
- `Lota::Graphics::Texture#filter`, `filter=`, `mipmap_filter`, `mipmap_filter=`, `wrap`, `wrap=`, `depth_sample_mode`, `depth_sample_mode=`, `generate_mipmaps`, `replace_pixels`, `texture_type`, `format`, `mipmap_mode`, `mipmap_count`, `layer_count`, `depth`, `pixel_width`, `pixel_height`, `pixel_dimensions`, `dpi_scale`, `msaa`, `debug_name`, `readable?`, `compressed?`, `format_linear?`, and `compute_writable?`, translating Texture's methods.
- `Lota::Graphics.set_canvas`, translating `love.graphics.setCanvas` with several canvases, a mipmap or a layer, and its table of canvases with `depthstencil:`, `depth:`, and `stencil:` as keywords (`set_canvas(canvas, stencil: true)`), each target alone or as `[texture, layer: 2, mipmap: 1]`; `canvas=` takes what `set_canvas` takes without options.
- `Lota::Graphics.readback_texture` reads a slice, a mipmap, a rectangle, and into an `ImageData` given, which it returns.
- `Lota::Graphics.draw` places a drawable by a `Lota::Math::Transform`, and `Lota::Graphics.draw_layer` translates `love.graphics.drawLayer`.
- A `Texture` the engine returns again, as `Lota::Graphics.canvas` returns the canvas set, is the same Ruby object, as LÖVE returns the same object.
- `Lota::Audio::Source#position`, `velocity`, `direction`, `cone`, `volume_limits`, and `attenuation_distances`, each with its writer of several values; `relative?` and `relative=`, `rolloff`, `air_absorption`, and their writers; `seek`, `tell`, and `duration` in `:seconds` or `:samples`; and `free_buffer_count`.
- `Lota::Audio.position`, `orientation`, `velocity`, `doppler_scale`, and `distance_model`, with their writers, translating the listener's functions of `love.audio`.
- `Lota::Graphics::Shader.new`, translating `love.graphics.newShader` with one or two sources, file names, or `FileData`, and `defines:`, `debugname:`, and `write:`; `Shader#send` and `send_color` for numbers, booleans, vectors and matrices as Arrays, a Transform, Textures, and a `Data`, with a matrix layout of `:row` or `:column`; and `warnings`, `uniform?`, `stage?`, `local_threadgroup_size`, and `debug_name`.
- `Lota::Graphics.shader` and `shader=`, translating `getShader` and `setShader`, and `Lota::Graphics.validate_shader`, which returns `[true]` or `[false, message]`.
- `Lota::Graphics::TextBatch.new`, translating `love.graphics.newTextBatch`, with `set`, `setf`, `add`, `addf`, `clear`, `font` and `font=`, `width`, `height`, and `dimensions`; text and its colors are as `print` takes them, `add` and `addf` return an index counting from 1, and `Lota::Graphics.draw` draws one.
- `Lota::Graphics::ImageFont.new`, translating `love.graphics.newImageFont` for a file name, a `FileData`, or an `ImageData`, with extra spacing and a DPI scale; it returns a `Font`, and `ImageFont === font` is true of every `Font`.
- `Lota::Graphics::Text.new`, translating LÖVE 12's deprecated `love.graphics.newText`: it makes a `TextBatch` and prints LÖVE's deprecation notice; `Text === x` is true of every `TextBatch`.
- `Lota::Graphics::Font.new` makes a BMFont from its definition and images, as `Font.new(definition, images, dpiscale)`.
- `Lota::Graphics.print` and `printf` take a `Lota::Math::Transform` in place of the position and numbers.
- `Lota::Window.update_mode`, `mode`, `desktop_dimensions`, and `safe_area`, translating `love.window.updateMode`, `getMode`, `getDesktopDimensions`, and `getSafeArea`; `mode` returns the width, the height, and a frozen `Lota::Window::Mode` of the settings, with LÖVE's field names.
- `Lota::System.os`, translating `love.system.getOS`.
- `Lota::Window.display_count`, `display_name`, `display_orientation` (a Symbol), `fullscreen_modes` (frozen `Lota::Window::FullscreenMode`s), `fullscreen` (the flag and the type, an Array), `set_fullscreen`, `position`, `position=`, `icon`, `set_icon`, `vsync`, `vsync=`, `display_sleep_enabled?`, `display_sleep_enabled=`, `focus?`, `mouse_focus?`, `visible?`, `occluded?`, `maximized?`, `minimized?`, `maximize`, `minimize`, `restore`, `focus`, `request_attention`, `dpi_scale`, `native_dpi_scale`, `to_pixels`, `from_pixels`, `system_theme` (a Symbol), and the deprecated `close`, translating the rest of `love.window` but `showFileDialog` and `getPointer`.
- `Lota::Window.show_message_box(title, message, type = nil, attachtowindow = true)` and, with an Array of buttons for its third argument, `show_message_box(title, message, buttons, type = nil, attachtowindow = true, enterbutton: nil, escapebutton: nil)`, translating `love.window.showMessageBox`; the second form returns the button pressed, counting from 1.
- `Lota::Keyboard.scancode_down?`, `key_repeat=`, `key_repeat?`, `text_input=` (an Array of the flag and a rectangle, by rule 6), `text_input?`, `screen_keyboard?`, `screen_keyboard_visible?`, `scancode_from_key`, `key_from_scancode` (both Symbols), and `modifier_active?`, translating the rest of `love.keyboard`; `down?` and `scancode_down?` also take LÖVE's table of keys as one Array.
- `Lota::Timer.fps`, `average_delta`, and `time`, translating `love.timer.getFPS`, `getAverageDelta`, and `getTime`.
- `Lota::System.processor_count`, `memory_size`, `power_info` (the state a Symbol, then the percent and seconds), `open_url`, `vibrate`, `background_music?`, and `preferred_locales`, translating the rest of `love.system`.
- `Lota::Event.wait` (deprecated, as in LÖVE), `restart`, and `modal_draw_callback=`, translating `love.event.wait`, `restart`, and `setModalDrawCallback`; `restart` carries every argument, `nil` included, as LÖVE does, but not yet a Lota object.
- `Lota::Event.push`, `restart`, and a modal draw callback's results carry tables, as LÖVE's do: an Array or a Hash goes in, and comes out of `poll` and `Lota.restart` as an Array when its keys are 1 to n and as a Hash otherwise, its numbers Floats and its Symbol keys Strings; a table that holds itself raises LÖVE's "Cycle detected in table".
- `Lota.version` (the major, minor, and revision numbers and the codename, an Array), `version_compatible?`, `deprecation_output=`, `deprecation_output?`, and `_version`, `_version_major`, `_version_minor`, `_version_revision`, `_version_codename`, `_version_compat`, and `_os`, translating `love.getVersion`, `isVersionCompatible`, `setDeprecationOutput`, `hasDeprecationOutput`, and LÖVE's version fields, defined in `Lota::Info`, a public module that `Lota` extends.
- `Lota::Mouse.visible=`, `visible?`, `grabbed=`, `grabbed?`, `set_relative_mode`, `relative_mode`, and `cursor_supported?`; `Lota::Graphics.created?` and `reset`; and `Lota::Window.open?`.
- `Lota::Sound::SoundData.new` and `Lota::Sound::Decoder.new`, translating `love.sound.newSoundData` (from a file, a `FileData`, a `Decoder`, or a sample count, rate, bit depth, and channel count) and `love.sound.newDecoder` (from a file with `:file` or `:memory`, or a `FileData`).
- `Lota::Sound::SoundData#channel_count`, `bit_depth`, `sample_rate`, `sample_count`, `duration`, `sample`, `sample=`, `copy_from`, and `slice`; `sample` and `sample=` read and store as LÖVE's LuaJIT code does, in double precision.
- `Lota::Data`, LÖVE's root type Data, which `SoundData`, `ImageData`, and `FileData` include, with `size`, `string`, `perform_atomic` (whose function is a block), `float`, `double`, `int8`, `int16`, `int32`, `uint8`, `uint16`, and `uint32`, translating Data's `getSize`, `getString`, `performAtomic`, `getFloat`, `getDouble`, `getInt8` to `getInt32`, and `getUInt8` to `getUInt32`; and `Lota.data`, for love.data, which `lota run` opens unless `t.modules.data = false`.
- `clone` and `dup` make LÖVE's copy of a `SoundData`, `Decoder`, `ImageData`, `FileData`, or `Lota::Audio::Source`, translating each one's `clone`.
- `Lota::Image::ImageData.new(width, height, format = :rgba8, rawdata = nil)`, `#pixel=`, and `#map_pixel`, translating `love.image.newImageData` with a size, `ImageData:setPixel`, and `ImageData:mapPixel`, whose function is a block; `#pixel` now reads as LÖVE's LuaJIT code does, in double precision and with its position rounded down, as do `#pixel=` and `#map_pixel`.
- `Lota::Native::RandomGenerator#random_normal` takes a mean after the standard deviation.
- `Lota::Physics` and `Lota.physics`, translating love.physics, which `lota run` opens unless `t.modules.physics = false`: `World`, `Body`, `Shape` with `CircleShape`, `PolygonShape`, `EdgeShape`, and `ChainShape`, `RectangleShape.new`, whose `===` is true of every `PolygonShape`, eleven `Joint` classes from `DistanceJoint` to `WheelJoint`, and `Contact`, with the methods Lövetest's physics tests call, `meter`, `meter=`, and `distance`; `Body#get_type` and `#set_type`, `Shape#get_type`, and `Joint#get_type` translate `getType` and `setType`; `World#query_shapes_in_area` and `#ray_cast` take blocks, and an engine object read back twice is the same Ruby object.
- `Lota::Physics::World#callbacks=` and `#callbacks`, translating `World:setCallbacks` and `getCallbacks`, take and give back the four contact callbacks (begin, end, pre-solve, and post-solve), and `World#contact_filter=` and `#contact_filter` translate `setContactFilter` and `getContactFilter`; each is anything that answers `call`, receives only as many of LÖVE's arguments as it declares, and runs within `World#update` as LÖVE's do, and the World keeps it alive until another replaces it or the World is destroyed.
- Dependency on Box2D 2.4, which LÖVE bundles, now linked into `Lota::Native` with LÖVE's physics module, which Lota changes with a patch of its own (`ext/lota/engine/physics.patch`).
- `Lota::Sound::Decoder#decode`, `channel_count`, `bit_depth`, `sample_rate`, and `duration`.
