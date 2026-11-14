#define WLR_USE_UNSTABLE

#include "Input.hpp"

#include <set>

static std::set<uint32_t> buttonsDown;

void trackPointerButton(const IPointer::SButtonEvent& e) {
    if (!e.mouse)
        return;

    if (e.state == WL_POINTER_BUTTON_STATE_PRESSED)
        buttonsDown.insert(e.button);
    else
        buttonsDown.erase(e.button);
}

bool pointerHeld() {
    return !buttonsDown.empty();
}
