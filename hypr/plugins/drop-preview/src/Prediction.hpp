#pragma once

#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <hyprland/src/helpers/math/Math.hpp>

#include <optional>

struct SDropPrediction {
    CBox      box;
    PHLWINDOW dragged;
};

std::optional<SDropPrediction> predictDrop(bool genericFallback);
