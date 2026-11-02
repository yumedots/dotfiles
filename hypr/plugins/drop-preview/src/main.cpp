#define WLR_USE_UNSTABLE

#include "Config.hpp"
#include "Input.hpp"
#include "Prediction.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/plugins/PluginSystem.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/BorderPassElement.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>

#include <chrono>
#include <cmath>

inline HANDLE PHANDLE = nullptr;

SConfig g_config;

struct SState {
    std::optional<CBox>                   goal;
    CBox                                  current;
    float                                 alpha = 0.F;
    bool                                  visible = false;
    std::chrono::steady_clock::time_point lastStep;
    std::vector<CHyprSignalListener>      listeners;
};

static SState g_state;

static CBox   damageBoxFor(const CBox& box) {
    return box.copy().expand(previewBorderSize() + 2);
}

static void damageCurrent() {
    if (g_state.visible)
        g_pHyprRenderer->damageBox(damageBoxFor(g_state.current));
}

static void hide() {
    damageCurrent();
    g_state.visible = false;
    g_state.alpha   = 0.F;
    g_state.goal.reset();
}

static CBox withSpacing(const CBox& box) {
    const auto SPACING = g_config.spacing->value();
    if (SPACING <= 0)
        return box;

    CBox shrunk = box.copy().expand(-sc<double>(SPACING));
    return shrunk.w < 1 || shrunk.h < 1 ? box : shrunk;
}

static bool approxEqual(const CBox& a, const CBox& b) {
    return std::abs(a.x - b.x) < 0.5 && std::abs(a.y - b.y) < 0.5 && std::abs(a.w - b.w) < 0.5 && std::abs(a.h - b.h) < 0.5;
}

static CBox lerpBox(const CBox& from, const CBox& to, double t) {
    return CBox{
        from.x + (to.x - from.x) * t,
        from.y + (to.y - from.y) * t,
        from.w + (to.w - from.w) * t,
        from.h + (to.h - from.h) * t,
    };
}

static void update() {
    if (!g_config.enabled->value()) {
        if (g_state.visible)
            hide();
        return;
    }

    const auto PREDICTION = pointerHeld() ? predictDrop(g_config.genericFallback->value()) : std::nullopt;

    if (!PREDICTION && (!g_layoutManager || !g_layoutManager->dragController()->target())) {
        if (g_state.visible)
            hide();
        return;
    }

    const auto  NOW      = std::chrono::steady_clock::now();
    const auto  DT       = g_state.visible ? std::chrono::duration<double>(NOW - g_state.lastStep).count() : 0.0;
    g_state.lastStep     = NOW;

    const CBox  OLD      = g_state.current;
    const float OLDALPHA = g_state.alpha;
    const bool  WASSHOWN = g_state.visible;

    if (PREDICTION) {
        const auto BOX = withSpacing(PREDICTION->box);
        if (!g_state.visible || g_state.alpha <= 0.F)
            g_state.current = BOX;
        g_state.goal    = BOX;
        g_state.visible = true;
    } else
        g_state.goal.reset();

    if (!g_state.visible)
        return;

    const double SPEED     = g_config.animSpeed->value();
    const double K         = SPEED <= 0 ? 1.0 : std::clamp(1.0 - std::exp(-SPEED * std::clamp(DT, 0.0, 0.1)), 0.0, 1.0);
    const float  FADESTEP  = sc<float>(SPEED <= 0 ? 1.0 : std::max(K, 0.05));

    if (g_state.goal) {
        g_state.current = K >= 1.0 || approxEqual(g_state.current, *g_state.goal) ? *g_state.goal : lerpBox(g_state.current, *g_state.goal, K);
        g_state.alpha   = std::min(1.F, g_state.alpha + FADESTEP);
    } else
        g_state.alpha = std::max(0.F, g_state.alpha - FADESTEP);

    if (!WASSHOWN || !approxEqual(OLD, g_state.current) || OLDALPHA != g_state.alpha) {
        if (WASSHOWN)
            g_pHyprRenderer->damageBox(damageBoxFor(OLD));
        g_pHyprRenderer->damageBox(damageBoxFor(g_state.current));
    }

    if (g_state.alpha <= 0.F && !g_state.goal)
        g_state.visible = false;
}

static CBox toDevicePixels(const CBox& logical, double scale) {
    const double X0 = std::round(logical.x * scale);
    const double Y0 = std::round(logical.y * scale);
    const double X1 = std::round((logical.x + logical.w) * scale);
    const double Y1 = std::round((logical.y + logical.h) * scale);

    return CBox{X0, Y0, std::max(1.0, X1 - X0), std::max(1.0, Y1 - Y0)};
}

static void draw() {
    if (!g_state.visible || g_state.alpha <= 0.F)
        return;

    const auto PMONITOR = g_pHyprRenderer->m_renderData.pMonitor.lock();
    if (!PMONITOR)
        return;

    CBox box = toDevicePixels(g_state.current.copy().translate(-PMONITOR->m_position), PMONITOR->m_scale);
    if (box.w < 1 || box.h < 1)
        return;

    const auto SCALE      = PMONITOR->m_scale;
    const auto ROUND      = std::round(previewRounding() * SCALE);
    const auto BORDER     = previewBorderSize();
    const auto ROUNDPOWR  = previewRoundingPower();
    const auto CORRECTION = BORDER * (M_SQRT2 - 1) * std::max(2.0 - ROUNDPOWR, 0.0);

    CHyprColor fill{sc<uint64_t>(g_config.colFill->value())};
    fill.a *= g_state.alpha;

    if (fill.a > 0.F) {
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(CRectPassElement::SRectData{
            .box           = box,
            .color         = fill,
            .round         = sc<int>(ROUND),
            .roundingPower = ROUNDPOWR,
            .blur          = g_config.blur->value(),
        }));
    }

    const CHyprColor BORDERCOL{sc<uint64_t>(g_config.colBorder->value())};
    if (BORDER > 0 && BORDERCOL.a > 0.F) {
        CBorderPassElement::SBorderData data;
        data.box           = box;
        data.grad1         = Config::CGradientValueData(BORDERCOL);
        data.round         = sc<int>(ROUND);
        data.outerRound    = sc<int>(std::round(((previewRounding() + BORDER) - CORRECTION) * SCALE));
        data.roundingPower = ROUNDPOWR;
        data.borderSize    = BORDER;
        data.a             = g_state.alpha;
        g_pHyprRenderer->m_renderPass.add(makeUnique<CBorderPassElement>(data));
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    if (g_pPluginSystem) {
        for (const auto* PLUGIN : g_pPluginSystem->getAllPlugins()) {
            if (PLUGIN && PLUGIN->m_name == "drop-preview" && PLUGIN->m_handle != handle)
                return {"drop-preview", "Shows where a dragged tiled window will be dropped", "gabriel", "1.0"};
        }
    }

    if (std::string{__hyprland_api_get_hash()} != std::string{__hyprland_api_get_client_hash()}) {
        HyprlandAPI::addNotification(PHANDLE, "[drop-preview] Version mismatch: rebuild against the running Hyprland", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[drop-preview] Version mismatch");
    }

    g_config.enabled    = makeShared<Config::Values::CBoolValue>("plugin:drop-preview:enabled", "Show where a dragged tiled window will land", true);
    g_config.colFill    = makeShared<Config::Values::CColorValue>("plugin:drop-preview:col.fill", "Preview fill color", 0x66202020);
    g_config.colBorder  = makeShared<Config::Values::CColorValue>("plugin:drop-preview:col.border", "Preview border color", 0xFF909090);
    g_config.borderSize = makeShared<Config::Values::CIntValue>("plugin:drop-preview:border_size", "Preview border size, -1 = general:border_size", -1,
                                                                Config::Values::SIntValueOptions{.min = -1, .max = 50});
    g_config.rounding   = makeShared<Config::Values::CIntValue>("plugin:drop-preview:rounding", "Preview corner rounding, -1 = decoration:rounding", -1,
                                                                Config::Values::SIntValueOptions{.min = -1, .max = 100});
    g_config.blur       = makeShared<Config::Values::CBoolValue>("plugin:drop-preview:blur", "Blur behind the preview fill", false);
    g_config.animSpeed  = makeShared<Config::Values::CFloatValue>("plugin:drop-preview:animation_speed", "Preview slide speed, 0 = snap instantly", 0.F);
    g_config.genericFallback =
        makeShared<Config::Values::CBoolValue>("plugin:drop-preview:generic_fallback", "On non-dwindle layouts, highlight the tiled window under the cursor", true);
    g_config.spacing = makeShared<Config::Values::CIntValue>("plugin:drop-preview:spacing", "Inset the preview from the drop area, in logical px", 8,
                                                             Config::Values::SIntValueOptions{.min = 0, .max = 200});

    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.enabled);

    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.colFill);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.colBorder);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.borderSize);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.rounding);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.blur);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.animSpeed);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.genericFallback);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.spacing);

    HyprlandAPI::reloadConfig();

    g_state.listeners.emplace_back(Event::bus()->m_events.render.pre.listen([](PHLMONITOR) { update(); }));
    g_state.listeners.emplace_back(Event::bus()->m_events.render.stage.listen([](eRenderStage stage) {
        if (stage == RENDER_POST_WINDOWS)
            draw();
    }));
    g_state.listeners.emplace_back(Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent e, Event::SCallbackInfo&) { trackPointerButton(e); }));

    return {"drop-preview", "Shows where a dragged tiled window will be dropped", "gabriel", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    hide();
    g_state.listeners.clear();
}
