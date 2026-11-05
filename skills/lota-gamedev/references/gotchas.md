# Gotchas for phones, touch, DPI, audio, and input

Two groups. The first is what a Lua developer on LÖVE meets too: LÖVE's
wiki and community answers apply. The second is where Lota differs from LÖVE
or has a gap: those can change in a release, so check the CHANGELOG. Names are
Lota's; the LÖVE function is in the RDoc.

## Same as in LÖVE

**Resolution and DPI**
- `t.highdpi = true` in `conf.rb` is needed for a sharp window on a high-DPI
  screen; without it LÖVE and Lota draw at 1x.
- Lay out in the units `Lota::Graphics.dimensions` returns. `Lota::Window.dpi_scale`
  is the factor to pixels; `Lota::Window.native_dpi_scale` is the real one.
  Methods are snake_case (`dpi_scale`); settings in `conf.rb` keep LÖVE's
  lowercase run-together spelling (`t.window.usedpiscale`).
- `t.window.usedpiscale = false` makes `dpi_scale` 1.0, so drawing, touch
  positions, and `Lota::Window.safe_area` are all in physical pixels.
- There is no physical-pixel-density API (LÖVE has none either): size touch
  targets in points and test on the smallest screen.

**Touch and mouse**
- A touchscreen sends `Lota.touchpressed(id, x, y, dx, dy, pressure, devicetype, mouse)`
  (and `touchmoved`, `touchreleased`), and SDL also sends a mouse event with
  `istouch` true. Handle the touch callbacks, and handle `mousepressed` only
  when `istouch` is false, or a tap counts twice.
- A touch iOS cancels (a system gesture) never gets `touchreleased`: clear your
  own touch state on a new press or on focus loss.
- A desktop mouse does not produce touches; on iPadOS a pointer does, with the
  last callback argument `mouse` true.

**Window, safe area, orientation**
- `Lota::Window.safe_area` returns `[x, y, width, height]`; read it at load and
  in `Lota.resize` and keep the HUD inside it.
- On iOS and Android the OS keeps the window fullscreen at the device's size,
  as it does for LÖVE; rebuild the layout in `Lota.resize` for rotation. LÖVE
  does not make `set_mode` special on phones; check the dimensions it gives
  you afterward instead of assuming the size you asked for.

**Input devices**
- Gamepads: use `Lota.joystickadded` / `joystickremoved` and keep the joysticks
  they hand you; ask `joystick.gamepad?` first. An accelerometer or a
  simulator may appear as a joystick.
- Sensors (`Lota::Sensor`) are absent on desktops and in the iOS Simulator:
  `Lota::Sensor.sensor?(:accelerometer)` is false there. Guard and degrade.
- Android's Back key arrives as `Lota.keypressed(:escape, :acback)`, and by
  default Android leaves the app on Back unless the app's host opts in to
  handling it. iOS has no Back key.
- A program that returns on iOS leaves the app on its last frame.

**Audio, files, shaders**
- With no audio device, LÖVE prints `Could not open device.` and plays nothing.
- Saves go where `Lota::Filesystem.save_directory` says, under your
  `t.identity`; a fused app saves where LÖVE's fused game saves.
- A shader compile error raises with LÖVE's message, line by line: build
  optional shaders inside a `rescue` and fall back, so a driver difference
  cannot stop the game.
- Graphics and window calls only work on the main thread and raise
  `ThreadError` elsewhere.

## Specific to Lota

**Gaps (not bound or not applied yet; see the CHANGELOG)**
- Audio effects, queueable sources, and `t.audio.mixwithsystem` in boot (LÖVE
  applies the last; on iOS set the audio session in the app's host instead:
  Ambient mixes with other apps and obeys the silent switch).
- Part of `love.physics` (for example some `Body` and `MouseJoint` setters),
  video, and `Lota::Thread` and channels (LÖVE's `love.thread`).
- A `NoMethodError` on a LÖVE function usually means it is not bound.

**Ruby-specific**
- A touch id is an Integer (LÖVE's light userdata); compare with `==`, fine as
  a Hash key.
- On phones, Ruby's `$stdout` is block-buffered when it is a pipe unless the
  runtime line-buffers it (Fledge 0.5.1 and later do): set `$stdout.sync = true`
  early so log lines arrive as they happen.
- Use Lota 0.1.3 or newer: earlier gems can crash a game that fetches the same
  engine object (`World#bodies`, `Joystick.joysticks`) every frame.

**Packaging** is in [shipping.md](shipping.md).
