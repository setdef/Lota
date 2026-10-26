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
-- Random numbers come from LÖVE's own generator, as Plan 001 has both
-- engines draw them: Lua's math.random and math.randomseed are pointed at
-- love.math.random and love.math.setRandomSeed (wrap_Math.lua:37-47),
-- which Lota::Math.random and Lota::Math.random_seed= port, and os.time()
-- with no table returns LOTA_PARITY_CLOCK, as Time.now does in
-- test/parity/probe.rb, so a game that seeds from the clock draws the same
-- numbers in both. Lua's own generator, which Ruby cannot reproduce, is
-- never reached. love.math opens after this file runs (boot.lua:347-372),
-- so the two are looked up when the game calls them.
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

assert(love.filesystem.mountFullPath(GAME, "/", "read", false), "could not mount " .. GAME)

if love.filesystem.getRealDirectory("conf.lua") == GAME then
  assert(love.filesystem.load("conf.lua"))()
end

local real_require = require
_G.require = function(name, ...)
  if name ~= "main" then
    return real_require(name, ...)
  end
  _G.require = real_require
  local main = real_require(name, ...)

  local frame = 0
  local update, draw = love.update, love.draw

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
    press_keys(frame + 1)
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
