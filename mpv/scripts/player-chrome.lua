-- Continuous charcoal panel behind uosc's persistent controls, plus the idle
-- backdrop. uosc publishes normalized margins, so the panel follows its sizing
-- and visibility. title-bar.lua owns the top of the window.
local mp = require("mp")
local assdraw = require("mp.assdraw")

local overlay = mp.create_osd_overlay("ass-events")
overlay.z = -1
local original_bottom = mp.get_property_number("video-margin-ratio-bottom", 0)

local function reserve_video_space(value)
  if math.abs(mp.get_property_number("video-margin-ratio-bottom", 0) - value) > 0.000001 then
    mp.set_property_number("video-margin-ratio-bottom", value)
  end
end

local function render()
  local dimensions = mp.get_property_native("osd-dimensions")
  local margins = mp.get_property_native("user-data/osc/margins")
  if not dimensions or dimensions.w <= 0 or dimensions.h <= 0 then
    overlay:remove()
    return
  end

  -- uosc otherwise removes middle buttons first, including Play/Pause.
  local expanded = dimensions.w >= 1000
  if mp.get_property_native("user-data/player-chrome/expanded") ~= expanded then
    mp.set_property_native("user-data/player-chrome/expanded", expanded)
  end
  if not margins then
    overlay:remove()
    return
  end

  local width, height = dimensions.w, dimensions.h
  local idle = mp.get_property_native("idle-active", false)
  -- Fit the whole picture above the persistent panel instead of covering it.
  -- uosc releases the margin when video playback controls fade away.
  reserve_video_space(math.max(original_bottom, margins.b or 0))
  local bottom = math.floor(height * (margins.b or 0) + 0.5)
  if bottom == 0 and not idle then
    overlay:remove()
    return
  end

  local ass = assdraw.ass_new()
  local function rectangle(y1, y2, color)
    ass:new_event()
    ass:pos(0, 0)
    ass:append("{\\an7\\bord0\\shad0\\1c&H" .. color .. "&}")
    ass:draw_start()
    ass:rect_cw(0, y1, width, y2)
    ass:draw_stop()
  end

  if idle then
    rectangle(0, height, "0E0E0E")
  end
  if bottom > 0 then
    rectangle(height - bottom, height, "1B1B1B")
    rectangle(height - bottom, height - bottom + 1, "222222")
  end

  overlay.res_x = width
  overlay.res_y = height
  overlay.data = ass.text
  overlay:update()
end

mp.observe_property("osd-dimensions", "native", render)
mp.observe_property("user-data/osc/margins", "native", render)
mp.observe_property("idle-active", "bool", render)
mp.register_event("shutdown", function()
  overlay:remove()
  mp.set_property_number("video-margin-ratio-bottom", original_bottom)
end)
