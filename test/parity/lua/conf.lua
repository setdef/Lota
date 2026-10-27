-- SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- The parity harness's Lua side: measurement code, not fixture code. It
-- runs a LÖVE game unchanged in the reference love, with a fixed dt and
-- scripted keys, and writes every frame the game shows to a PNG file, so
-- test/parity/probe.rb can compare the same game in Lota frame by frame.
--
-- Run as:
--
--   LOTA_PARITY_GAME=/abs/game LOTA_PARITY_FRAMES_DIR=/abs/frames \
--   LOTA_PARITY_FRAMES=240 LOTA_PARITY_FPS=60 LOTA_PARITY_CLOCK=1600000000 \
--   LOTA_PARITY_HOLD=79:31-60,80:91-150 LOTA_PARITY_PRESS=41:240-240 \
--   love test/parity/lua
--
-- boot.lua loads this conf.lua before anything of the game's (boot.lua:
-- 249-251, when love.conf is not yet set). It mounts the game ahead of
-- this folder (love.filesystem.mountFullPath with append false,
-- wrap_Filesystem.cpp:155-172), so the game's own conf.lua, main.lua, and
-- files are the ones LÖVE finds; loads the game's conf.lua, if it has one;
-- and wraps the global require, which boot.lua calls for "main"
-- (boot.lua:444), so that once the game's main.lua has defined its
-- callbacks, love.update and love.draw are wrapped:
--
-- * love.update holds each scripted key down, or lets it up, then calls
--   the game's love.update with 1 / LOTA_PARITY_FPS instead of the time
--   the frame took. love.keyboard.isDown reads SDL's keyboard state
--   (keyboard/sdl/Keyboard.cpp:56-72), so the keys are written there,
--   through LuaJIT's FFI, after love.run has handled the frame's events
--   and before the game reads them. LOTA_PARITY_HOLD lists
--   scancode:first-last, the frames (counting from 1) a key is held, by
--   SDL's scancode (SDL_scancode.h). The state is all a held key gets: no
--   keypressed or keyreleased event is queued.
-- * LOTA_PARITY_PRESS lists keys pressed, in the same form: each is held
--   for its frames, as above, and also goes down and comes up as a player's
--   key does, with SDL's key events. love.update pushes them into SDL's
--   queue after the game's love.update, with SDL_PushEvent, so love.run's
--   next love.event.pump turns them into keypressed and keyreleased
--   (event/sdl/Event.cpp:284-317): the key goes down at the start of its
--   first frame and comes up at the start of the frame after its last. It
--   writes the key's state as it pushes the event, as SDL does when it
--   reads a key from the system (SDL_SendKeyboardKey), so the state agrees
--   with the event when the game hears of it. An event SDL reads from macOS
--   reaches the game only while its window has keyboard focus; one pushed
--   into the queue does not depend on focus at all.
-- * love.draw calls the game's love.draw, then asks for a screenshot of
--   the frame (love.graphics.captureScreenshot, which LÖVE takes in
--   love.graphics.present, after love.draw returns), saved as
--   LOTA_PARITY_FRAMES_DIR/NNNN.png. After frame LOTA_PARITY_FRAMES it
--   quits, as the game would with love.event.quit, so the game's love.quit
--   runs, unless a pressed key comes up after that frame: then quitting is
--   the game's to do, as on Escape. A game still running at the next
--   frame's love.update did not, and the harness quits with status 1.
--
-- * The mouse moves and clicks as LOTA_PARITY_MOVE and LOTA_PARITY_CLICK
--   say. LOTA_PARITY_MOVE lists frame:x:y, the frame a move comes at the
--   start of and the position in the window it goes to, starting with
--   frame 1, where the pointer starts. The pointer is held at the latest
--   move's position, as keys are held: love.load first puts it at the
--   start, and love.update puts it where the next frame has it after the
--   game's love.update, every frame, with love.mouse.setPosition, which
--   warps the system's pointer and so updates SDL's mouse state, which
--   love.mouse.getPosition reads (mouse/sdl/Mouse.cpp:131-164), and
--   queues SDL's mousemoved event when the pointer moves. Holding it every
--   frame puts the pointer back where the script has it should macOS put
--   off a warp, as it does while the window is being moved or takes focus
--   (SDL 3.4.10, src/video/cocoa/SDL_cocoamouse.m, Cocoa_WarpMouseGlobal),
--   or should anything else move the pointer.
--   LOTA_PARITY_CLICK lists button:first-last, a button as LÖVE numbers it
--   and the frames it is down in: love.update pushes SDL's button down
--   event, where SDL's mouse state says the pointer is, before its first
--   frame, and the button up event before the frame after its last, which
--   LÖVE turns into mousepressed and mousereleased
--   (event/sdl/Event.cpp:354-384). SDL keeps the buttons that are down to
--   itself, so love.mouse.isDown does not see a click. A move comes before
--   a click in the same frame.
-- * love.timer.getDelta returns 1 / LOTA_PARITY_FPS, the dt love.update
--   gets, rather than the time the frame took.
--
-- Random numbers come from LÖVE's own generator, as Plan 001 has both
-- engines draw them: Lua's math.random and math.randomseed are pointed at
-- love.math.random and love.math.setRandomSeed (wrap_Math.lua:37-47),
-- which Lota::Math.random and Lota::Math.random_seed= port, and os.time()
-- with no table returns LOTA_PARITY_CLOCK, as Time.now does in
-- test/parity/probe.rb, so a game that seeds from the clock draws the same
-- numbers in both. Lua's own generator, which Ruby cannot reproduce, is
-- never reached. love.math opens after this file runs (boot.lua:347-372),
-- so the two are looked up when the game calls them. LÖVE seeds its
-- generator from the real time when love.math opens
-- (math/MathModule.cpp:203-210), so the harness seeds it with
-- LOTA_PARITY_CLOCK before the game's love.load, as the Ruby side does,
-- for a game that draws numbers without seeding them.
--
-- The game's own code is not changed, and runs as love.run calls it.

local GAME = assert(os.getenv("LOTA_PARITY_GAME"), "LOTA_PARITY_GAME is not set")
local FRAMES_DIR = assert(os.getenv("LOTA_PARITY_FRAMES_DIR"), "LOTA_PARITY_FRAMES_DIR is not set")
local FRAMES = assert(tonumber(os.getenv("LOTA_PARITY_FRAMES")), "LOTA_PARITY_FRAMES is not a number")
local DT = 1 / assert(tonumber(os.getenv("LOTA_PARITY_FPS")), "LOTA_PARITY_FPS is not a number")
local CLOCK = assert(tonumber(os.getenv("LOTA_PARITY_CLOCK")), "LOTA_PARITY_CLOCK is not a number")

local real_time = os.time
os.time = function(date)
  if date ~= nil then
    return real_time(date)
  end
  return CLOCK
end
math.random = function(...)
  return love.math.random(...)
end
math.randomseed = function(...)
  return love.math.setRandomSeed(...)
end

-- The keys LOTA_PARITY_HOLD or LOTA_PARITY_PRESS names, in its order.
local function keys(variable)
  local list = {}
  for scancode, first, last in (os.getenv(variable) or ""):gmatch("(%d+):(%d+)-(%d+)") do
    table.insert(list, { scancode = tonumber(scancode), first = tonumber(first), last = tonumber(last) })
  end
  return list
end

local holds = keys("LOTA_PARITY_HOLD")
local presses = keys("LOTA_PARITY_PRESS")
for _, press in ipairs(presses) do
  table.insert(holds, press)
end

-- Whether a pressed key comes up after the last frame, so that the game,
-- not the harness, ends the run.
local game_quits = false
for _, press in ipairs(presses) do
  game_quits = game_quits or press.last == FRAMES
end

-- SDL 3's keyboard event and the event union it travels in (SDL_events.h:
-- SDL_KeyboardEvent, and SDL_Event's 128 bytes of padding), as the native
-- test extension builds them in C++ (ext/lota/native_test, press_key).
local ffi = require("ffi")
ffi.cdef([[
const bool *SDL_GetKeyboardState(int *numkeys);
typedef struct {
  uint32_t type;
  uint32_t reserved;
  uint64_t timestamp;
  uint32_t windowID;
  uint32_t which;
  int scancode;
  uint32_t key;
  uint16_t mod;
  uint16_t raw;
  bool down;
  bool repeat;
} LotaParityKeyboardEvent;
typedef union {
  uint32_t type;
  LotaParityKeyboardEvent key;
  uint8_t padding[128];
} LotaParityEvent;
bool SDL_PushEvent(LotaParityEvent *event);
uint32_t SDL_GetKeyFromScancode(int scancode, uint16_t modstate, bool key_event);
uint64_t SDL_GetTicksNS(void);
const char *SDL_GetError(void);
]])

local SDL_EVENT_KEY_DOWN = 0x300
local SDL_EVENT_KEY_UP = 0x301

local function keyboard_state()
  return ffi.cast("bool *", ffi.C.SDL_GetKeyboardState(nil))
end

-- Each scripted key's state in frame number +frame+. A key listed twice
-- is down when either range holds it.
local function hold_keys(frame)
  local state = keyboard_state()
  local down = {}
  for _, hold in ipairs(holds) do
    down[hold.scancode] = down[hold.scancode] or (frame >= hold.first and frame <= hold.last)
  end
  for scancode, value in pairs(down) do
    state[scancode] = value
  end
end

-- Pushes SDL's event for the key with +scancode+ going down, or coming
-- up, with the key SDL would give it (SDL_GetKeyFromScancode with
-- key_event true, as SDL_SendKeyboardKey calls it), and writes its state.
local function press_key(scancode, down)
  local event = ffi.new("LotaParityEvent")
  event.key.type = down and SDL_EVENT_KEY_DOWN or SDL_EVENT_KEY_UP
  event.key.timestamp = ffi.C.SDL_GetTicksNS()
  event.key.scancode = scancode
  event.key.key = ffi.C.SDL_GetKeyFromScancode(scancode, 0, true)
  event.key.down = down
  keyboard_state()[scancode] = down
  assert(ffi.C.SDL_PushEvent(event), ffi.string(ffi.C.SDL_GetError()))
end

-- Queues the key events due at the start of frame number +frame+.
local function press_keys(frame)
  for _, press in ipairs(presses) do
    if press.first == frame then
      press_key(press.scancode, true)
    end
    if press.last + 1 == frame then
      press_key(press.scancode, false)
    end
  end
end

-- The moves LOTA_PARITY_MOVE lists, in its order.
local moves = {}
for frame, x, y in (os.getenv("LOTA_PARITY_MOVE") or ""):gmatch("(%d+):(%-?[%d%.]+):(%-?[%d%.]+)") do
  table.insert(moves, { frame = tonumber(frame), x = tonumber(x), y = tonumber(y) })
end

-- The clicks LOTA_PARITY_CLICK lists, in the form of the keys above, with
-- a button for a scancode.
local clicks = keys("LOTA_PARITY_CLICK")

-- SDL 3's mouse button event (SDL_events.h: SDL_MouseButtonEvent), in an
-- event union of its own, as the keyboard's above, and the call that reads
-- where SDL's mouse state has the pointer (SDL_mouse.h).
ffi.cdef([[
typedef struct {
  uint32_t type;
  uint32_t reserved;
  uint64_t timestamp;
  uint32_t windowID;
  uint32_t which;
  uint8_t button;
  bool down;
  uint8_t clicks;
  uint8_t padding;
  float x;
  float y;
} LotaParityMouseButtonEvent;
typedef union {
  uint32_t type;
  LotaParityMouseButtonEvent button;
  uint8_t padding[128];
} LotaParityMouseEvent;
uint32_t SDL_GetMouseState(float *x, float *y);
]])

local SDL_EVENT_MOUSE_BUTTON_DOWN = 0x401
local SDL_EVENT_MOUSE_BUTTON_UP = 0x402

-- SDL's number for LÖVE's mouse button +button+: LÖVE's 2 is the right
-- button, SDL's 3, and LÖVE's 3 the middle, SDL's 2 (event/sdl/Event.cpp:
-- 357-367).
local function sdl_button(button)
  if button == 2 then
    return 3
  elseif button == 3 then
    return 2
  end
  return button
end

-- Pushes SDL's event for mouse button +button+ going down, or coming up,
-- as a single click, where SDL's mouse state says the pointer is.
local function click_mouse(button, down)
  local event = ffi.new("LotaParityMouseEvent")
  local x, y = ffi.new("float[1]"), ffi.new("float[1]")
  ffi.C.SDL_GetMouseState(x, y)
  event.button.type = down and SDL_EVENT_MOUSE_BUTTON_DOWN or SDL_EVENT_MOUSE_BUTTON_UP
  event.button.timestamp = ffi.C.SDL_GetTicksNS()
  event.button.button = sdl_button(button)
  event.button.down = down
  event.button.clicks = 1
  event.button.x = x[0]
  event.button.y = y[0]
  assert(ffi.C.SDL_PushEvent(ffi.cast("LotaParityEvent *", event)), ffi.string(ffi.C.SDL_GetError()))
end

-- Holds the pointer where the latest move by frame number +frame+ put it,
-- unless the script moves it not at all.
local function hold_pointer(frame)
  local held = nil
  for _, move in ipairs(moves) do
    if move.frame <= frame then
      held = move
    end
  end
  if held then
    love.mouse.setPosition(held.x, held.y)
  end
end

-- Holds the pointer, and queues the clicks, for frame number +frame+.
local function use_mouse(frame)
  hold_pointer(frame)
  for _, click in ipairs(clicks) do
    if click.first == frame then
      click_mouse(click.scancode, true)
    end
    if click.last + 1 == frame then
      click_mouse(click.scancode, false)
    end
  end
end

-- AppKit's run loop mode while a dialog is up, and the Objective-C runtime
-- calls that find the dialog and press its default button
-- (objc/runtime.h, objc/message.h). objc_msgSend must be called through a
-- pointer of each method's own type, never as a variadic function, which
-- passes its arguments differently on Apple silicon.
ffi.cdef([[
typedef void *LotaParityId;
LotaParityId objc_getClass(const char *name);
LotaParityId sel_registerName(const char *name);
void objc_msgSend(void);
typedef void (*LotaParityTimerCallBack)(void *timer, void *info);
void *CFRunLoopTimerCreate(void *allocator, double fireDate, double interval, unsigned long flags, long order,
                           LotaParityTimerCallBack callout, void *context);
void CFRunLoopAddTimer(void *loop, void *timer, void *mode);
void *CFRunLoopGetMain(void);
double CFAbsoluteTimeGetCurrent(void);
void *CFStringCreateWithCString(void *allocator, const char *string, uint32_t encoding);
]])

local send = ffi.cast("LotaParityId (*)(LotaParityId, LotaParityId)", ffi.C.objc_msgSend)
local send_id = ffi.cast("void (*)(LotaParityId, LotaParityId, LotaParityId)", ffi.C.objc_msgSend)
local kCFStringEncodingUTF8 = 0x08000100

-- Presses Return on every dialog the game shows, as a player would, so a
-- dialog such as LÖVE's version warning (boot.lua:378-393) does not wait
-- for good. SDL shows its message box with NSAlert's runModal
-- (SDL_ShowMessageBox, vendor/love/src/modules/window/sdl/Window.cpp),
-- which runs the main run loop in AppKit's modal panel mode until a button
-- is pressed, so a timer in that mode, every tenth of a second, finds the
-- modal window and presses its default button, the one Return presses
-- (NSWindow's defaultButtonCell, which NSAlert gives its first button).
-- It does this in the game's own process, as the key events above are
-- pushed into SDL's queue, so it needs neither keyboard focus nor macOS's
-- Accessibility permission, which System Events would need to press
-- Return from another process. ext/lota/native_test does the same for
-- Lota (press_return_on_dialogs).
local press_return = ffi.cast("LotaParityTimerCallBack", function()
  local application = send(ffi.C.objc_getClass("NSApplication"), ffi.C.sel_registerName("sharedApplication"))
  local dialog = send(application, ffi.C.sel_registerName("modalWindow"))
  if dialog == nil then
    return
  end
  local button = send(dialog, ffi.C.sel_registerName("defaultButtonCell"))
  if button ~= nil then
    send_id(button, ffi.C.sel_registerName("performClick:"), nil)
  end
end)
ffi.C.CFRunLoopAddTimer(ffi.C.CFRunLoopGetMain(),
  ffi.C.CFRunLoopTimerCreate(nil, ffi.C.CFAbsoluteTimeGetCurrent() + 0.1, 0.1, 0, 0, press_return, nil),
  ffi.C.CFStringCreateWithCString(nil, "NSModalPanelRunLoopMode", kCFStringEncodingUTF8))

assert(love.filesystem.mountFullPath(GAME, "/", "read", false), "could not mount " .. GAME)

if love.filesystem.getRealDirectory("conf.lua") == GAME then
  assert(love.filesystem.load("conf.lua"))()
end

-- Keeps LÖVE from becoming the active program, as ext/lota/native_test
-- keeps Lota (stay_in_background in dialogs.mm): the harness starts both
-- with SDL's hints that keep a window from activating its program
-- (test/test_helper.rb), but AppKit activates a program that runs a modal
-- dialog, as SDL's message box does, which would take keyboard focus from
-- the person at the computer. A program whose activation policy is
-- prohibited (NSApplicationActivationPolicyProhibited, 2) is never
-- activated, and still shows its windows and dialogs. SDL has made the
-- application once love.window has opened, whose Window starts SDL's video
-- subsystem (window/sdl/Window.cpp:88-90), and boot.lua shows its version
-- warning only after every module has opened (boot.lua:347-393).
local send_long = ffi.cast("void (*)(LotaParityId, LotaParityId, long)", ffi.C.objc_msgSend)
local function stay_in_background()
  local application = send(ffi.C.objc_getClass("NSApplication"), ffi.C.sel_registerName("sharedApplication"))
  send_long(application, ffi.C.sel_registerName("setActivationPolicy:"), 2)
end

-- The parity harness's audio device (ext/lota/native_test/loopback.cpp),
-- which the harness loads into this process with DYLD_INSERT_LIBRARIES
-- (test/parity/parity_helper.rb), so that love.audio opens an OpenAL Soft
-- loopback device, which mixes only when told to. love.update tells it to
-- mix the frame's dt after the game's love.update, once a frame, so a
-- sound the game played in the frame, from love.update or from an event
-- love.run handled before it, starts at the frame's first sample, however
-- fast the frame ran. The samples go to LOTA_LOOPBACK_FILE, which Lota's
-- run writes too, from the same place in its frame (test/parity/probe.rb).
ffi.cdef([[
long lota_loopback_render(const char *path, double dt);
]])

local LOOPBACK_FILE = os.getenv("LOTA_LOOPBACK_FILE")

local function mix_audio()
  if love.audio then
    assert(ffi.C.lota_loopback_render(assert(LOOPBACK_FILE, "LOTA_LOOPBACK_FILE is not set"), DT) >= 0,
      "the loopback device is not open, or cannot write its file")
  end
end

-- The sound files LOTA_PARITY_SOUNDS lists, by absolute path, separated
-- by commas, each decoded by love.sound as a game would decode it, into
-- LOTA_PARITY_SOUNDS_DIR, so test/parity/probe.rb's decoding in Lota can
-- be compared with LÖVE's, sample for sample. For the Nth file, N.sounddata
-- holds what love.sound.newSoundData makes of it, and N.decoder what
-- love.sound.newDecoder decodes from it, piece by piece: a line of the
-- format each reports, then the samples' bytes as getString gives them,
-- each Decoder piece after a line with its size. The file is read with
-- Lua's io, since it need not be in the game's folder, into a FileData
-- named as the file, as love.filesystem.newFileData names one. Both run in
-- love.load, before the game's, once every module is open.
local function decode_sounds()
  local dir = os.getenv("LOTA_PARITY_SOUNDS_DIR")
  if not dir then
    return
  end
  local number = 0
  for path in (os.getenv("LOTA_PARITY_SOUNDS") or ""):gmatch("[^,]+") do
    number = number + 1
    local source = assert(io.open(path, "rb"))
    local contents = source:read("*a")
    source:close()
    local name = path:match("[^/]+$")

    local sounddata = love.sound.newSoundData(love.filesystem.newFileData(contents, name))
    local out = assert(io.open(string.format("%s/%d.sounddata", dir, number), "wb"))
    out:write(string.format("%d %d %d %d %.17g %d\n", sounddata:getSampleRate(), sounddata:getBitDepth(),
      sounddata:getChannelCount(), sounddata:getSampleCount(), sounddata:getDuration(), sounddata:getSize()))
    out:write(sounddata:getString())
    out:close()

    local decoder = love.sound.newDecoder(love.filesystem.newFileData(contents, name))
    out = assert(io.open(string.format("%s/%d.decoder", dir, number), "wb"))
    out:write(string.format("%d %d %d %.17g\n", decoder:getSampleRate(), decoder:getBitDepth(),
      decoder:getChannelCount(), decoder:getDuration()))
    local piece = decoder:decode()
    while piece do
      local bytes = piece:getString()
      out:write(string.format("%d\n", #bytes))
      out:write(bytes)
      piece = decoder:decode()
    end
    out:close()
  end
end

local real_require = require
_G.require = function(name, ...)
  if name == "love.window" then
    local window = real_require(name, ...)
    stay_in_background()
    return window
  end
  if name ~= "main" then
    return real_require(name, ...)
  end
  _G.require = real_require
  local main = real_require(name, ...)

  local frame = 0
  local update, draw, load = love.update, love.draw, love.load

  if love.timer then
    love.timer.getDelta = function()
      return DT
    end
  end

  love.load = function(...)
    decode_sounds()
    if love.math then
      love.math.setRandomSeed(CLOCK)
    end
    if love.mouse then
      hold_pointer(1)
    end
    if load then
      return load(...)
    end
  end

  love.update = function(dt)
    frame = frame + 1
    if frame > FRAMES then
      print(string.format("The game did not quit after frame %d.", FRAMES))
      love.event.quit(1)
      return
    end
    hold_keys(frame)
    if update then
      update(DT)
    end
    mix_audio()
    press_keys(frame + 1)
    use_mouse(frame + 1)
  end

  love.draw = function()
    if draw then
      draw()
    end
    local number = frame
    if number > FRAMES then
      return
    end
    love.graphics.captureScreenshot(function(imagedata)
      local file = assert(io.open(string.format("%s/%04d.png", FRAMES_DIR, number), "wb"))
      file:write(imagedata:encode("png"):getString())
      file:close()
      if number == FRAMES and not game_quits then
        love.event.quit()
      end
    end)
  end

  return main
end
