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
--   LOTA_PARITY_FRAMES=240 LOTA_PARITY_FPS=60 \
--   LOTA_PARITY_HOLD=79:31-60,80:91-150 love test/parity/lua
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
--   SDL's scancode (SDL_scancode.h). The state is all the keys get: no
--   keypressed or keyreleased event is queued.
-- * love.draw calls the game's love.draw, then asks for a screenshot of
--   the frame (love.graphics.captureScreenshot, which LÖVE takes in
--   love.graphics.present, after love.draw returns), saved as
--   LOTA_PARITY_FRAMES_DIR/NNNN.png. After frame LOTA_PARITY_FRAMES it
--   quits, as the game would with love.event.quit, so the game's love.quit
--   runs.
--
-- The game's own code is not changed, and runs as love.run calls it.

local GAME = assert(os.getenv("LOTA_PARITY_GAME"), "LOTA_PARITY_GAME is not set")
local FRAMES_DIR = assert(os.getenv("LOTA_PARITY_FRAMES_DIR"), "LOTA_PARITY_FRAMES_DIR is not set")
local FRAMES = assert(tonumber(os.getenv("LOTA_PARITY_FRAMES")), "LOTA_PARITY_FRAMES is not a number")
local DT = 1 / assert(tonumber(os.getenv("LOTA_PARITY_FPS")), "LOTA_PARITY_FPS is not a number")

local holds = {}
for scancode, first, last in (os.getenv("LOTA_PARITY_HOLD") or ""):gmatch("(%d+):(%d+)-(%d+)") do
  table.insert(holds, { scancode = tonumber(scancode), first = tonumber(first), last = tonumber(last) })
end

local ffi = require("ffi")
ffi.cdef([[const bool *SDL_GetKeyboardState(int *numkeys);]])

-- Each scripted key's state in frame number +frame+. A key listed twice
-- is down when either range holds it.
local function hold_keys(frame)
  local state = ffi.cast("bool *", ffi.C.SDL_GetKeyboardState(nil))
  local down = {}
  for _, hold in ipairs(holds) do
    down[hold.scancode] = down[hold.scancode] or (frame >= hold.first and frame <= hold.last)
  end
  for scancode, value in pairs(down) do
    state[scancode] = value
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
    hold_keys(frame)
    if update then
      update(DT)
    end
  end

  love.draw = function()
    if draw then
      draw()
    end
    local number = frame
    love.graphics.captureScreenshot(function(imagedata)
      local file = assert(io.open(string.format("%s/%04d.png", FRAMES_DIR, number), "wb"))
      file:write(imagedata:encode("png"):getString())
      file:close()
      if number == FRAMES then
        love.event.quit()
      end
    end)
  end

  return main
end
