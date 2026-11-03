-- xmake tasks: link lint bench hypr vm doctor (see scripts/tasks.sh)

target("checks")
    set_kind("phony")
    add_tests("daemon")
    add_tests("qml")
    add_tests("idle-spawn")
    on_test(function (target, opt)
        local name = opt.name:match("/(.+)$")

        if name == "daemon" then
            return os.execv("sh", {"-c", "cd daemon && zig build test"}, {try = true}) == 0
        end

        if name == "qml" then
            return os.execv("sh", {"-c", "node shell/ui/AgentFace.check.js"}, {try = true}) == 0
        end

        if name == "idle-spawn" then
            return os.execv("sh", {"-c", "scripts/yudae spawn-check --seconds 10"}, {try = true}) == 0
        end

        return false
    end)
