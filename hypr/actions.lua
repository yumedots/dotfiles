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

return {
    floatToggle = floatToggle,
}
