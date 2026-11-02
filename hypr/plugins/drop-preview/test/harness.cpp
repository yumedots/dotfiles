#define WLR_USE_UNSTABLE

#include "../src/Config.hpp"
#include "../src/Prediction.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/pointer/PointerController.hpp>

#include <fstream>
#include <format>
#include <lua.hpp>

inline HANDLE PHANDLE = nullptr;

SConfig g_config;

static void pressButton(bool pressed) {
    IPointer::SButtonEvent e;
    e.button = 272;
    e.mouse  = true;
    e.state  = pressed ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED;
    Event::SCallbackInfo info;
    Event::bus()->m_events.input.mouse.button.emit(e, info);
}

static PHLWINDOW windowByClass(const std::string& cls) {
    for (const auto& w : Desktop::windowState()->windows()) {
        if (w->m_class == cls && w->m_isMapped)
            return w;
    }
    return nullptr;
}

static void report(const std::string& line) {
    std::ofstream("/tmp/dp-results.txt", std::ios::app) << line << '\n';
}

static int luaRun(lua_State* L) {
    const std::string CLS = luaL_checkstring(L, 1);
    const Vector2D    START{luaL_checknumber(L, 2), luaL_checknumber(L, 3)};
    const Vector2D    END{luaL_checknumber(L, 4), luaL_checknumber(L, 5)};

    const auto        WINDOW = windowByClass(CLS);
    if (!WINDOW) {
        lua_pushstring(L, "no window");
        return 1;
    }

    pressButton(true);
    Pointer::pointerController()->warpTo(START, true);
    g_layoutManager->beginDragTarget(WINDOW->layoutTarget(), MBIND_MOVE);
    Pointer::pointerController()->warpTo(END, true);
    g_layoutManager->moveMouse(END);

    const auto PRED = predictDrop(false);

    g_layoutManager->endDragTarget();
    pressButton(false);

    const auto ACT = WINDOW->geometricBox(Desktop::View::IGeometric::GEOMETRIC_GOAL);

    std::string out = PRED ? std::format("pred={:.0f},{:.0f},{:.0f},{:.0f}", PRED->box.x, PRED->box.y, PRED->box.w, PRED->box.h) : std::string{"pred=none"};
    out += std::format(" actual={:.0f},{:.0f},{:.0f},{:.0f} floating={}", ACT.x, ACT.y, ACT.w, ACT.h, WINDOW->m_isFloating);
    report(std::format("{} ({:.0f},{:.0f}) {}", CLS, END.x, END.y, out));
    lua_pushstring(L, out.c_str());
    return 1;
}

static int luaBegin(lua_State* L) {
    const std::string CLS = luaL_checkstring(L, 1);
    const Vector2D    END{luaL_checknumber(L, 2), luaL_checknumber(L, 3)};

    const auto        WINDOW = windowByClass(CLS);
    if (WINDOW) {
        pressButton(true);
        Pointer::pointerController()->warpTo(WINDOW->layoutBox().middle(), true);
        g_layoutManager->beginDragTarget(WINDOW->layoutTarget(), MBIND_MOVE);
        Pointer::pointerController()->warpTo(END, true);
        g_layoutManager->moveMouse(END);
    }

    lua_pushstring(L, WINDOW ? "ok" : "no window");
    return 1;
}

static int luaFinish(lua_State* L) {
    if (g_layoutManager->dragController()->target())
        g_layoutManager->endDragTarget();
    pressButton(false);
    lua_pushstring(L, "ok");
    return 1;
}

static int luaState(lua_State* L) {
    const auto& DRAG = g_layoutManager->dragController();
    const auto  OUT  = std::format("target={} tiled={} mode={}", DRAG->target() != nullptr, DRAG->draggingTiled(), sc<int>(DRAG->mode()));
    report(OUT);
    lua_pushstring(L, OUT.c_str());
    return 1;
}

static int luaMove(lua_State* L) {
    const Vector2D P{luaL_checknumber(L, 1), luaL_checknumber(L, 2)};
    Pointer::pointerController()->warpTo(P, true);
    g_layoutManager->moveMouse(P);
    lua_pushstring(L, "ok");
    return 1;
}

static int luaProbe(lua_State* L) {
    const auto PRED = predictDrop(true);
    const auto OUT  = PRED ? std::format("box={:.1f},{:.1f} {:.1f}x{:.1f}", PRED->box.x, PRED->box.y, PRED->box.w, PRED->box.h) : std::string{"none"};
    report(OUT);
    lua_pushstring(L, OUT.c_str());
    return 1;
}

static int luaValues(lua_State* L) {
    const auto OUT = std::format("rounding={} border={} power={:.2f}", previewRounding(), previewBorderSize(), previewRoundingPower());
    report(OUT);
    lua_pushstring(L, OUT.c_str());
    return 1;
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;
    HyprlandAPI::addLuaFunction(PHANDLE, "dptest", "run", luaRun);
    HyprlandAPI::addLuaFunction(PHANDLE, "dptest", "begin", luaBegin);
    HyprlandAPI::addLuaFunction(PHANDLE, "dptest", "finish", luaFinish);
    HyprlandAPI::addLuaFunction(PHANDLE, "dptest", "values", luaValues);
    HyprlandAPI::addLuaFunction(PHANDLE, "dptest", "state", luaState);
    HyprlandAPI::addLuaFunction(PHANDLE, "dptest", "move", luaMove);
    HyprlandAPI::addLuaFunction(PHANDLE, "dptest", "probe", luaProbe);
    return {"dptest", "drop-preview test harness", "gabriel", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    ;
}
