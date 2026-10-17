local versions = 10
local namedPrefix = "name:v"

local function slotOf(name)
	local slot = tonumber(name or "")

	if slot then
		return slot, 1
	end

	local left, right = string.match(name or "", "^v(%d+)%.(%d+)$")

	if not left then
		return nil
	end

	return tonumber(left), tonumber(right)
end

local function target(slot, version)
	if version <= 1 then
		return slot
	end

	return namedPrefix .. slot .. "." .. version
end

local function wrap(version, delta)
	return (version - 1 + delta) % versions + 1
end

local function current()
	local workspace = hl.get_active_workspace()

	return slotOf(workspace and workspace.name)
end

local function jump(version)
	local slot = current()

	if not slot or version < 1 or version > versions then
		return
	end

	hl.dispatch(hl.dsp.focus({ workspace = target(slot, version) }))
end

local function step(delta)
	local slot, version = current()

	if slot then
		jump(wrap(version, delta))
	end
end

return {
	versions = versions,
	slotOf = slotOf,
	target = target,
	wrap = wrap,
	jump = jump,
	step = step
}
