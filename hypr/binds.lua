local programs = require("programs")
local actions = require("actions")
local mainMod = "SUPER"

hl.config({ binds = { scroll_event_delay = 0 } })

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
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(programs.terminal))
hl.bind(mainMod .. " + W", hl.dsp.window.close(), { repeating = true })
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(programs.session))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(programs.fileManager))
hl.bind(mainMod .. " + SPACE", actions.floatToggle)
hl.bind("ALT + SPACE", hl.dsp.global("quickshell:launcher"))
hl.bind(mainMod .. " + TAB", hl.dsp.global("quickshell:windows"))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

local resizeStep = 40

hl.bind(mainMod .. " + CTRL + ALT + right", hl.dsp.window.resize({ x = resizeStep, y = 0, relative = true }),  { repeating = true })
hl.bind(mainMod .. " + CTRL + ALT + left",  hl.dsp.window.resize({ x = -resizeStep, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + ALT + up",    hl.dsp.window.resize({ x = 0, y = resizeStep, relative = true }),  { repeating = true })
hl.bind(mainMod .. " + CTRL + ALT + down",  hl.dsp.window.resize({ x = 0, y = -resizeStep, relative = true }), { repeating = true })

hl.bind(mainMod .. " + F", hl.dsp.global("quickshell:media"))
hl.bind(mainMod .. " + Z", hl.dsp.global("quickshell:cpu"))
hl.bind(mainMod .. " + X", hl.dsp.global("quickshell:memory"))
hl.bind(mainMod .. " + C", hl.dsp.global("quickshell:volume"))
hl.bind(mainMod .. " + A", hl.dsp.global("quickshell:calendar"))
hl.bind(mainMod .. " + S", actions.scratchpadSwap)
hl.bind(mainMod .. " + O", hl.dsp.global("quickshell:notifications"))
hl.bind(mainMod .. " + D", hl.dsp.global("quickshell:contributions"))
hl.bind(mainMod .. " + P", hl.dsp.global("quickshell:display"))

hl.bind(mainMod .. " + left",  focusOrSwitch("left"))
hl.bind(mainMod .. " + right", focusOrSwitch("right"))
hl.bind(mainMod .. " + up",    focusOrSwitch("up"))
hl.bind(mainMod .. " + down",  focusOrSwitch("down"))

hl.bind(mainMod .. " + ALT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + ALT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + ALT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + ALT + down",  hl.dsp.window.move({ direction = "down" }))

hl.bind(mainMod .. " + SHIFT + S", hl.dsp.workspace.toggle_special("magic"))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86AudioNext",  hl.dsp.global("quickshell:mediaNext"),      { locked = true })
hl.bind("XF86AudioPause", hl.dsp.global("quickshell:mediaPlayPause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.global("quickshell:mediaPlayPause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.global("quickshell:mediaPrevious"),  { locked = true })
