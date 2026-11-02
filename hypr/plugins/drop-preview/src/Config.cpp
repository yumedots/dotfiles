#define WLR_USE_UNSTABLE

#include "Config.hpp"

#include <hyprland/src/config/ConfigValue.hpp>

static auto PBORDERSIZE   = CConfigValue<Config::INTEGER>("general:border_size");
static auto PROUNDING     = CConfigValue<Config::INTEGER>("decoration:rounding");
static auto PROUNDINGPOWR = CConfigValue<Config::FLOAT>("decoration:rounding_power");

int previewBorderSize() {
    const auto SIZE = g_config.borderSize ? g_config.borderSize->value() : -1;
    return SIZE < 0 ? *PBORDERSIZE : sc<int>(SIZE);
}

int previewRounding() {
    const auto ROUND = g_config.rounding ? g_config.rounding->value() : -1;
    return ROUND < 0 ? *PROUNDING : sc<int>(ROUND);
}

float previewRoundingPower() {
    return *PROUNDINGPOWR;
}
