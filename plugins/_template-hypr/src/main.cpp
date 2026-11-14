#define WLR_USE_UNSTABLE

#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

inline HANDLE PHANDLE = nullptr;

static SP<Config::Values::CBoolValue> g_enabled;

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    g_enabled = makeShared<Config::Values::CBoolValue>("plugin:template-hypr:enabled", "Enable the template plugin", true);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_enabled);
    HyprlandAPI::reloadConfig();

    HyprlandAPI::addNotification(PHANDLE, "[template-hypr] loaded", CHyprColor{0.4F, 0.6F, 1.0F, 1.0F}, 3000);

    return {"template-hypr", "Minimal Hyprland plugin template", "yudae", "0.1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
}
