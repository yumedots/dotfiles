local ran = 0

local function assert(condition, message)
	ran = ran + 1

	if not condition then
		error(message, 2)
	end
end

local binds = {}
local dispatches = {}
local state = { active = nil, windows = {} }

hl = {
	config = function () end,
	on = function () end,
	bind = function (key, handler) binds[key] = handler end,
	get_active_window = function () return state.active end,
	get_windows = function () return state.windows end,
	get_layers = function () return {} end,
	get_monitors = function () return {} end,
	get_workspace = function () return nil end,
	get_last_window = function () return nil end,
	get_window = function (sel)
		for _, w in ipairs(state.windows) do
			if "address:" .. w.address == sel then
				return w
			end
		end

		return nil
	end,
	exec_cmd = function (cmd) table.insert(dispatches, { kind = "exec", cmd = cmd }) end,
	dispatch = function (dsp)
		table.insert(dispatches, dsp)

		-- the stub layout really toggles: side by side becomes stacked, first
		-- window on top, and the reads stay live so a stale-geometry bug would
		-- not be masked
		if dsp.kind == "layout" and dsp.name == "togglesplit" and #state.windows == 2 then
			local y = math.min(state.windows[1].at.y, state.windows[2].at.y)

			for i, w in ipairs(state.windows) do
				w.at.x = 0
				w.at.y = y + (i - 1) * 340
				w.size.x = 1262
				w.size.y = 330
			end
		end

		-- swap({ next = true }) trades the two windows' places in the stack
		if dsp.kind == "swap" and #state.windows == 2 then
			local a, b = state.windows[1], state.windows[2]
			a.at.y, b.at.y = b.at.y, a.at.y
		end
	end,
	dsp = {
		window = {
			move = function (args) return { kind = "move", args = args } end,
			swap = function (args) return { kind = "swap", args = args } end,
			close = function () return { kind = "close" } end,
			resize = function () return { kind = "resize" } end,
			float = function () return { kind = "float" } end,
			center = function () return { kind = "center" } end,
			drag = function () return { kind = "drag" } end,
			fullscreen = function () return { kind = "fullscreen" } end,
			bring_to_top = function () return { kind = "top" } end,
		},
		focus = function (args) return { kind = "focus", args = args } end,
		layout = function (name) return { kind = "layout", name = name } end,
		workspace = {
			move = function () return { kind = "wsmove" } end,
			toggle_special = function () return { kind = "special" } end,
		},
		global = function () return { kind = "global" } end,
		exec_cmd = function (cmd) return { kind = "exec", cmd = cmd } end,
		exit = function () return { kind = "exit" } end,
	},
}

package.path = "hypr/?.lua;" .. package.path

local function win(address, x, y, w, h)
	return {
		address = address,
		at = { x = x, y = y },
		size = { x = w, y = h },
		mapped = true,
		hidden = false,
		floating = false,
		workspace = { id = 1 },
	}
end

local function fire(key)
	dispatches = {}

	if type(binds[key]) == "function" then
		binds[key]()
	else
		hl.dispatch(binds[key])
	end

	return dispatches
end

local function kinds(list)
	local out = {}

	for _, d in ipairs(list) do
		table.insert(out, d.kind .. (d.name and (":" .. d.name) or "") .. (d.args and d.args.direction and (":" .. d.args.direction) or ""))
	end

	return table.concat(out, ",")
end

local up = "SUPER + ALT + up"

require("binds")

assert(binds[up] ~= nil, "the up move bind exists")
assert(binds["SUPER + ALT + left"] ~= nil, "the left move bind exists")

local left = win("0x1", 9, 41, 626, 670)
local right = win("0x2", 645, 41, 626, 670)

local function sideBySide()
	left.at.x, left.at.y, left.size.x, left.size.y = 9, 41, 626, 670
	right.at.x, right.at.y, right.size.x, right.size.y = 645, 41, 626, 670
end

local function stacked()
	left.at.x, left.at.y, left.size.x, left.size.y = 9, 41, 1262, 330
	right.at.x, right.at.y, right.size.x, right.size.y = 9, 381, 1262, 330
end

state.active = right
state.windows = { left, right }
sideBySide()
assert(kinds(fire(up)) == "layout:togglesplit,swap", "side by side, right window, moving up toggles then swaps it to the top")

state.active = left
state.windows = { left, right }
sideBySide()
assert(kinds(fire(up)) == "layout:togglesplit", "side by side, left window, moving up toggles and lands it on top already")

state.active = left
state.windows = { left, right }
stacked()
assert(kinds(fire(up)) == "move:up", "already stacked, moving up just moves")

state.active = left
state.windows = { left, right }
stacked()
assert(kinds(fire("SUPER + ALT + down")) == "move:down", "stacked, moving down just moves")

state.active = right
state.windows = { left, right }
sideBySide()
assert(kinds(fire("SUPER + ALT + down")) == "layout:togglesplit", "side by side, right window, moving down toggles and it already landed low")

state.active = left
state.windows = { left, right }
sideBySide()
assert(kinds(fire("SUPER + ALT + down")) == "layout:togglesplit,swap", "side by side, left window, moving down toggles then swaps it to the bottom")

state.active = right
state.windows = { left, right }
sideBySide()
assert(kinds(fire("SUPER + ALT + left")) == "move:left", "side by side, moving left just moves")

local third = win("0x3", 9, 41, 400, 670)
state.active = right
state.windows = { left, right, third }
sideBySide()
assert(kinds(fire(up)) == "move:up", "three windows keep the plain move")

state.active = nil
state.windows = {}
assert(kinds(fire(up)) == "move:up", "no window, no crash")

print("check ok (" .. ran .. " assertions)")
