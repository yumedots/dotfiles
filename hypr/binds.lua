local programs = require("programs")
local actions = require("actions")
local mainMod = "SUPER"

local function switcherOpen()
    for _, layer in ipairs(hl.get_layers({ namespace = "launcher" })) do
        if layer.interactivity == 1 then return true end
    end

    return false
end

local function focusOrSwitch(direction)
    return function()
        if switcherOpen() then
            hl.exec_cmd("qs ipc call shell windowsStep " .. direction)
            return
        end

        hl.dispatch(hl.dsp.focus({ direction = direction }))
    end
end

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(programs.terminal))
hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(programs.session))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(programs.fileManager))
hl.bind(mainMod .. " + SPACE", actions.floatToggle)
hl.bind("ALT + SPACE", hl.dsp.exec_cmd(programs.menu))
hl.bind(mainMod .. " + TAB", hl.dsp.exec_cmd(programs.windowSwitcher))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd(programs.cpu))
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd(programs.memory))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(programs.volume))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(programs.calendar))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd(programs.notifications))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(programs.contributions))

hl.bind(mainMod .. " + left",  focusOrSwitch("left"))
hl.bind(mainMod .. " + right", focusOrSwitch("right"))
hl.bind(mainMod .. " + up",    focusOrSwitch("up"))
hl.bind(mainMod .. " + down",  focusOrSwitch("down"))

hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

hl.bind(mainMod .. " + G",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
