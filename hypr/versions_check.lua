local dispatched = {}
local events = {}
local state = { name = "4" }

hl = {
    get_active_workspace = function () return { name = state.name } end,
    dispatch = function (dispatcher) dispatched[#dispatched + 1] = dispatcher.workspace end,
    dsp = { focus = function (selector) return selector end },
    on = function (event, callback) events[event] = callback end,
}

local versions = dofile("hypr/versions.lua")

assert(type(events["workspace.active"]) == "function", "versions listen for the workspace you land on")

local function last()
    return dispatched[#dispatched]
end

assert(versions.target(4, 1) == 4, "the base version is the plain workspace")
assert(versions.target(4, 2) == "name:v4.2", "a version is the named workspace of its slot")
assert(select(1, versions.slotOf("v12.10")) == 12, "a version name recovers the slot")
assert(select(2, versions.slotOf("v12.10")) == 10, "a version name recovers the version")
assert(select(1, versions.slotOf("7")) == 7, "a plain workspace is the base version")
assert(versions.slotOf("special:magic") == nil, "an unrelated workspace has no versions")
assert(versions.wrap(10, 1) == 1, "stepping past the last version wraps to the first")
assert(versions.wrap(1, -1) == 10, "stepping below the first version wraps to the last")
assert(versions.wrap(5, 1) == 6, "a step in the middle just moves")

state.name = "v4.3"
versions.step(1)
assert(last() == "name:v4.4", "stepping up goes to the next version of the focused slot")

state.name = "v4.3"
versions.step(-1)
assert(last() == "name:v4.2", "stepping down goes to the previous version")

state.name = "v4.2"
versions.step(-1)
assert(last() == 4, "stepping below the first version lands on the base workspace")

state.name = "v4.2"
versions.jump(1)
assert(last() == 4, "jumping to the base version lands on the base workspace")

state.name = "5"
versions.jump(5)
assert(last() == "name:v5.5", "jumping from a plain workspace keeps its slot")

state.name = "v9.10"
versions.jump(10)
assert(last() == "name:v9.10", "jumping to a version already shown does nothing new")

state.name = "special:magic"
local count = #dispatched
versions.jump(5)
versions.step(1)
assert(#dispatched == count, "a workspace of its own has no versions")

state.name = "v6.3"
local calls = #dispatched
versions.landing({ name = "v6.3", id = -1 })
assert(#dispatched == calls, "a versioned landing only remembers the version it holds")

state.name = "6"
calls = #dispatched
versions.landing("6")
assert(#dispatched == calls + 1 and last() == "name:v6.3", "returning to a slot lands on the version it held")

state.name = "v6.3"
versions.jump(1)
assert(last() == 6, "jumping to the base version lands on the base workspace")

state.name = "6"
calls = #dispatched
versions.landing("6")
assert(#dispatched == calls, "the base version picked by hand is not yanked back")

calls = #dispatched
versions.landing("8")
assert(#dispatched == calls, "a slot that never held a version stays on the base one")

state.name = "v8.5"
calls = #dispatched
versions.visit(8, 5)
assert(#dispatched == calls + 1 and last() == "name:v8.5", "visiting a version focuses it")

state.name = "8"
calls = #dispatched
versions.landing("8")
assert(last() == "name:v8.5", "a visited slot returns to the version it was visited on")

calls = #dispatched
versions.visit(8, 1)
assert(last() == 8, "visiting the base version lands on the plain workspace")

state.name = "8"
calls = #dispatched
versions.landing("8")
assert(#dispatched == calls, "the visited base version is not yanked back")

for _, target in ipairs(dispatched) do
    assert(target ~= "special:magic", "versions never touch an unrelated workspace")
end

print("versions: ok")
