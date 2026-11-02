#pragma once

#include <hyprland/src/devices/IPointer.hpp>

void trackPointerButton(const IPointer::SButtonEvent& e);
bool pointerHeld();
