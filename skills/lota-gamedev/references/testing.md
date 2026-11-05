# Testing a Lota game

## What can run without a window

Keep rules, scoring, layout math, and state machines in plain Ruby classes that
never call Lota, and test them with Minitest under `bundle exec rake test`.
That is most of a game, and it needs no display.

## What needs a window

Drawing needs a real window: SDL's offscreen mode cannot make a Metal or OpenGL
context on macOS. On Linux use a display (Xvfb with Mesa is what Lota's own CI
uses). Write an end-to-end smoke mode into the game: an environment variable
that makes it quit by itself after a few seconds with status 0, print one
identifying line, and save a frame:

```ruby
Lota::Graphics.capture_screenshot("frame.png") # written to Lota::Filesystem.save_directory
```

`capture_screenshot` reads the game's own next frame, so it needs no desktop
focus and is not skewed by other windows.

## Never disturb the person at the computer

A test must not imitate or block the person's mouse or keyboard. Windows a test
opens should stay in the background; Lota's tests set SDL's hints
`SDL_MAC_BACKGROUND_APP=1`, `SDL_WINDOW_ACTIVATE_WHEN_SHOWN=0`, and
`SDL_WINDOW_ACTIVATE_WHEN_RAISED=0` in the environment of anything they start.
A step that truly needs the keyboard, pointer, or focus should hold
`desktop_input_lock` ([github.com/setdef/DesktopInputLock](https://github.com/setdef/DesktopInputLock)):
`DesktopInputLock.hold(speak: true) { ... }`, which asks the person aloud and
with a banner to step away, and waits for any other process that holds it.

## Evidence to gather and what it can and cannot show

A CI runner has no GPU and no audio device: it can show that the game starts,
draws with software rendering, saves, and exits. It cannot show real GPU
behavior, real audio output, touch on a real screen, a gamepad, or performance.
Say which you proved; do not claim a real-device result from a runner.
