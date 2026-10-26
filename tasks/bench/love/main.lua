-- SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- rake bench's game for the reference love (tasks/bench.rb), measurement
-- code written for the benchmark, as tasks/bench/lota/main.rb is Lota's.
-- It runs one scenario, named by LOTA_BENCH_SCENARIO, and writes what it
-- measured to LOTA_BENCH_REPORT as JSON, then quits.
--
-- Each frame scenario makes LOTA_BENCH_DRAWS calls from love.draw, in the
-- same loop as the Ruby game, so the two engines draw the same
-- rectangles. The first LOTA_BENCH_WARMUP frames run untimed; then each of
-- LOTA_BENCH_FRAMES frames is timed twice, as Bench::Recorder times them:
-- the draw loop alone, and the whole frame, from the start of one
-- love.draw to the start of the next. The scenario "calls" instead times
-- single calls, each over and over, the best of five runs, as
-- Bench.per_call does.

local SCENARIO = assert(os.getenv("LOTA_BENCH_SCENARIO"), "LOTA_BENCH_SCENARIO is not set")
local REPORT = assert(os.getenv("LOTA_BENCH_REPORT"), "LOTA_BENCH_REPORT is not set")
local DRAWS = tonumber(os.getenv("LOTA_BENCH_DRAWS") or "10000")
local WARMUP = tonumber(os.getenv("LOTA_BENCH_WARMUP") or "200")
local FRAMES = tonumber(os.getenv("LOTA_BENCH_FRAMES") or "2000")
local CALLS = tonumber(os.getenv("LOTA_BENCH_CALLS") or "200000")

local graphics = love.graphics
local getTime = love.timer.getTime

local scenarios = {}

function scenarios.rectangle()
  for i = 0, DRAWS - 1 do
    graphics.rectangle("fill", (i % 100) * 8, math.floor(i / 100) * 6, 4, 4)
  end
end

function scenarios.set_color()
  for i = 0, DRAWS - 1 do
    graphics.setColor((i % 8) * 0.125, (i % 4) * 0.25, (i % 2) * 0.5, 1.0)
    graphics.rectangle("fill", (i % 100) * 8, math.floor(i / 100) * 6, 4, 4)
  end
end

function scenarios.color_reader()
  for i = 0, DRAWS - 1 do
    graphics.getColor()
    graphics.rectangle("fill", (i % 100) * 8, math.floor(i / 100) * 6, 4, 4)
  end
end

local calls = {
  { "empty function", function() end },
  { "love.graphics.getWidth", function() graphics.getWidth() end },
  { "love.graphics.getColor", function() graphics.getColor() end },
  { "love.graphics.getDimensions", function() graphics.getDimensions() end },
  { "love.graphics.setColor(r, g, b, a)", function() graphics.setColor(0.25, 0.5, 0.75, 1.0) end },
  { "love.graphics.rectangle", function() graphics.rectangle("fill", 8, 6, 4, 4) end },
}

-- Seconds per call of +call+, the best of five runs of CALLS calls.
local function per_call(call)
  local best = math.huge
  for _ = 1, 5 do
    local start = getTime()
    for _ = 1, CALLS do
      call()
    end
    best = math.min(best, getTime() - start)
  end
  return best / CALLS
end

local function encode(value)
  local kind = type(value)
  if kind == "number" then
    return string.format("%.17g", value)
  elseif kind == "string" then
    return string.format("%q", value)
  elseif kind == "table" and #value > 0 then
    local items = {}
    for _, item in ipairs(value) do
      table.insert(items, encode(item))
    end
    return "[" .. table.concat(items, ",") .. "]"
  elseif kind == "table" then
    local items = {}
    for key, item in pairs(value) do
      table.insert(items, string.format("%q", key) .. ":" .. encode(item))
    end
    return "{" .. table.concat(items, ",") .. "}"
  end
  error("cannot encode a " .. kind)
end

local function write(results)
  local name, version, vendor, device = graphics.getRendererInfo()
  results.engine = "love"
  results.scenario = SCENARIO
  results.jit = jit and (jit.status() and "luajit" or "luajit, JIT off") or "lua"
  results.lua = jit and jit.version or _VERSION
  results.renderer = table.concat({ name, version, vendor, device }, ", ")
  results.draws = DRAWS
  local file = assert(io.open(REPORT, "w"))
  file:write(encode(results))
  file:close()
  love.event.quit()
end

if SCENARIO ~= "calls" and not scenarios[SCENARIO] then
  error("unknown scenario " .. SCENARIO)
end

local drawn, open = 0, nil
local draw_times, frame_times = {}, {}

function love.draw()
  if SCENARIO == "calls" then
    local results = {}
    for _, call in ipairs(calls) do
      results[call[1]] = { seconds = per_call(call[2]) }
    end
    write({ calls = results })
    return
  end

  local start = getTime()
  if open then
    table.insert(frame_times, start - open)
    open = nil
  end
  if #frame_times >= FRAMES then
    write({ draw = draw_times, frame = frame_times })
    return
  end

  local timed = drawn >= WARMUP
  drawn = drawn + 1
  scenarios[SCENARIO]()
  if timed then
    table.insert(draw_times, getTime() - start)
    open = start
  end
end
