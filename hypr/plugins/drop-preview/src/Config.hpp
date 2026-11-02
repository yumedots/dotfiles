#pragma once

#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>

struct SConfig {
    SP<Config::Values::CBoolValue>  enabled;
    SP<Config::Values::CColorValue> colFill;
    SP<Config::Values::CColorValue> colBorder;
    SP<Config::Values::CIntValue>   borderSize;
    SP<Config::Values::CIntValue>   rounding;
    SP<Config::Values::CBoolValue>  blur;
    SP<Config::Values::CFloatValue> animSpeed;
    SP<Config::Values::CBoolValue>  genericFallback;
};

extern SConfig g_config;

int           previewBorderSize();
int           previewRounding();
float         previewRoundingPower();
