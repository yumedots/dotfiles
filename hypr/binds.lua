local programs = require("programs")
local actions = require("actions")
local mainMod = "SUPER"
local launcherConfig = "$HOME/.config/quickshell/launcherShell.qml"

hl.config({ binds = { scroll_event_delay = 0 } })

local function switcherOpen()
    for _, layer in ipairs(hl.get_layers({ namespace = "launcher" })) do
        if layer.interactivity == 1 then return true end
    end

    return false
end

local function closeWidgetsCommand()
    local command = ""

    if hl.get_layers({ namespace = "launcher" })[1] then
        command = command .. "qs ipc -p " .. launcherConfig .. " call shell killPopupsLocal 2>/dev/null; "
    end

    if hl.get_layers({ namespace = "tooltip" })[1] then
        command = command .. "qs ipc call shell closeBarPopups 2>/dev/null; "
    end

    return command
end

local function wakeLauncher(action)
    local ipc = "qs ipc -p " .. launcherConfig .. " call shell " .. action
    local start = "ulimit -Sn 65536; export MALLOC_ARENA_MAX=2 MALLOC_TRIM_THRESHOLD_=65536 QSG_RENDER_LOOP=basic; setsid quickshell -p " .. launcherConfig
    local wake = "sleep 0.5; " .. ipc .. " 2>/dev/null || { sleep 0.4; " .. ipc .. "; }"

    return hl.dsp.exec_cmd(ipc .. " 2>/dev/null || { " .. start .. " >/dev/null 2>&1 & " .. wake .. "; }")
end

local function gotoWorkspace(workspace)
    return function()
        local close = closeWidgetsCommand()

        if close == "" then
            hl.dispatch(hl.dsp.focus({ workspace = workspace }))
            return
        end

        local target = type(workspace) == "number" and tostring(workspace) or "\"" .. workspace .. "\""

        hl.exec_cmd(close .. "hyprctl dispatch 'hl.dsp.focus({workspace = " .. target .. "})'")
    end
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
    hl.bind(mainMod .. " + " .. key,         gotoWorkspace(i))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(programs.terminal))
hl.bind(mainMod .. " + W", hl.dsp.window.close(), { repeating = true })
hl.bind("F11", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(programs.session))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(programs.fileManager))
hl.bind(mainMod .. " + SPACE", actions.floatToggle)
hl.bind("ALT + SPACE", wakeLauncher("launcher"))
hl.bind(mainMod .. " + TAB", wakeLauncher("windows"))
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

hl.bind(mainMod .. " + mouse_down", gotoWorkspace("+1"))
hl.bind(mainMod .. " + mouse_up",   gotoWorkspace("-1"))

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
