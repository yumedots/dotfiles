local versions = 10
local namedPrefix = "name:v"
local sticky = {}

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

	sticky[slot] = version
	hl.dispatch(hl.dsp.focus({ workspace = target(slot, version) }))
end

local function step(delta)
	local slot, version = current()

	if slot then
		jump(wrap(version, delta))
	end
end

local function nameOf(workspace)
	if type(workspace) == "string" then
		return workspace
	end

	if type(workspace) == "number" then
		return tostring(workspace)
	end

	if workspace then
		return workspace.name and tostring(workspace.name)
	end

	return nil
end

local function landing(workspace)
	local slot, version = slotOf(nameOf(workspace))

	if not slot then
		return
	end

	if version > 1 then
		sticky[slot] = version
		return
	end

	local wanted = sticky[slot] or 1

	if wanted > 1 then
		hl.dispatch(hl.dsp.focus({ workspace = target(slot, wanted) }))
	end
end

if hl.on then
	hl.on("workspace.active", landing)
end

return {
	versions = versions,
	slotOf = slotOf,
	target = target,
	wrap = wrap,
	jump = jump,
	step = step,
	landing = landing
}
