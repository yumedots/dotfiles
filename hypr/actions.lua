local FLOAT_SCALE = 0.7
local shrunk = {}

local function floatToggle()
    local win = hl.get_active_window()
    if not win or not win.mapped then return end

    if win.floating then
        hl.dispatch(hl.dsp.window.float({ action = "unset" }))
        return
    end

    local tiledW, tiledH = 0, 0
    if type(win.size) == "table" then
        tiledW, tiledH = win.size.x or 0, win.size.y or 0
    end
    hl.dispatch(hl.dsp.window.float({ action = "set" }))

    local fwin = hl.get_active_window()
    if fwin and type(fwin.size) == "table" and tiledW > 0
       and not shrunk[win.address]
       and (fwin.size.x or 0) >= tiledW * 0.95 then
        shrunk[win.address] = true
        hl.dispatch(hl.dsp.window.resize({ x = math.floor(tiledW * FLOAT_SCALE), y = math.floor(tiledH * FLOAT_SCALE) }))
        hl.dispatch(hl.dsp.window.center())
    end
end

local CASCADE_STEP = 40

-- windows and monitors are measured in logical pixels, the monitor only reports
-- its physical size, so the screen edge is divided back by the scale
local function cascadeTo(win, last)
    local monitor = win.monitor
    local size = type(win.size) == "table" and win.size or nil
    local at = type(last.at) == "table" and last.at or nil
    if not monitor or not size then return end

    local right = monitor.x + monitor.width / monitor.scale
    local bottom = monitor.y + monitor.height / monitor.scale
    local x = (at and at.x or monitor.x) + CASCADE_STEP
    local y = (at and at.y or monitor.y) + CASCADE_STEP

    if x + (size.x or 0) > right or y + (size.y or 0) > bottom then
        x, y = monitor.x + CASCADE_STEP, monitor.y + CASCADE_STEP
    end

    hl.dispatch(hl.dsp.window.move({ x = math.floor(x), y = math.floor(y) }))
end

-- ponytail: a window opening while the last focused one floats floats too, so a
-- round of floating windows stays floating, and each one lands a step down and
-- right of that last one until the screen runs out and the stair starts over.
-- hl.dsp.window.float toggles in this build -- the action field it takes is
-- ignored -- so the guard on win.floating is what makes the call a set.
-- Ceiling: only the last focused window is looked at, one toggle per open, and
-- the bar's reserved strip is not counted when the stair wraps.
local function followFloat(win)
    local last = hl.get_last_window()
    if not last or last.address == win.address or not last.floating or win.floating then return end

    hl.dispatch(hl.dsp.window.float({ window = "address:" .. win.address }))
    cascadeTo(hl.get_window("address:" .. win.address) or win, last)
end

local function scratchpadSwap()
    local win = hl.get_active_window()
    if not win then return end

    if not (win.workspace and win.workspace.special) then
        hl.dispatch(hl.dsp.window.move({ window = win, workspace = "special:magic", follow = false }))
        return
    end

    local special = hl.get_workspace("special:magic")
    local target
    for _, m in ipairs(hl.get_monitors()) do
        if m.focused then target = m.active_workspace end
    end
    if not target or target.special then return end

    if special and special.windows == 1 and special.visible then
        hl.dispatch(hl.dsp.workspace.toggle_special("magic"))
    end
    hl.dispatch(hl.dsp.window.move({ window = win, workspace = target }))
end

hl.on("window.open", followFloat)

return {
    floatToggle = floatToggle,
    scratchpadSwap = scratchpadSwap,
}
