hl.config({
	general = {
		gaps_in = 0,
		gaps_out = 0,
		border_size = 0,
		resize_on_border = false,
	},

	decoration = {
		rounding = 0,
		blur = { enabled = false },
		shadow = { enabled = false },
	},

	animations = {
		enabled = false,
	},

	input = {
		kb_layout = "us",
		kb_variant = "",
		numlock_by_default = true,
	},

	misc = {
		disable_hyprland_logo = true,
		force_default_wallpaper = 0,
		disable_splash_rendering = true,
	},
})

local shell = os.getenv("QS_GREETER_SHELL") or "/home/gabriel/.config/quickshell/greeterShell.qml"

hl.on("hyprland.start", function()
	hl.exec_cmd("/usr/bin/quickshell -p \"" .. shell .. "\"; hyprctl dispatch 'hl.dsp.exit()'")
end)
