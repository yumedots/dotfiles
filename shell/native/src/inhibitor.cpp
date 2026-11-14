#include "inhibitor.h"

#include <wayland-client.h>

#include <cstring>

#include "inhibitor-client-protocol.h"

struct WaylandInhibitor::Private {
	wl_display *display = nullptr;
	wl_registry *registry = nullptr;
	zwp_keyboard_shortcuts_inhibit_manager_v1 *manager = nullptr;
	wl_seat *seat = nullptr;
	wl_surface *surface = nullptr;
	zwp_keyboard_shortcuts_inhibitor_v1 *inhibitor = nullptr;
	bool active = false;
};

namespace {

void onActive(void *data, zwp_keyboard_shortcuts_inhibitor_v1 *) {
	static_cast<WaylandInhibitor::Private *>(data)->active = true;
}

void onInactive(void *data, zwp_keyboard_shortcuts_inhibitor_v1 *) {
	static_cast<WaylandInhibitor::Private *>(data)->active = false;
}

const zwp_keyboard_shortcuts_inhibitor_v1_listener inhibitorListener = {onActive, onInactive};

void onGlobal(void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t) {
	auto *d = static_cast<WaylandInhibitor::Private *>(data);
	if (strcmp(interface, zwp_keyboard_shortcuts_inhibit_manager_v1_interface.name) != 0) return;
	d->manager = static_cast<zwp_keyboard_shortcuts_inhibit_manager_v1 *>(
		wl_registry_bind(registry, name, &zwp_keyboard_shortcuts_inhibit_manager_v1_interface, 1));
}

void onGlobalRemove(void *, wl_registry *, uint32_t) {}

const wl_registry_listener registryListener = {onGlobal, onGlobalRemove};

} // namespace

WaylandInhibitor::WaylandInhibitor() : d(new Private) {}

WaylandInhibitor::~WaylandInhibitor() {
	inhibit(false);
	if (d->registry) wl_registry_destroy(d->registry);
	if (d->manager) zwp_keyboard_shortcuts_inhibit_manager_v1_destroy(d->manager);
	delete d;
}

void WaylandInhibitor::setSurface(wl_display *display, wl_seat *seat, wl_surface *surface) {
	d->display = display;
	d->seat = seat;
	d->surface = surface;
}

void WaylandInhibitor::inhibit(bool on) {
	if (!on) {
		if (d->inhibitor) {
			zwp_keyboard_shortcuts_inhibitor_v1_destroy(d->inhibitor);
			d->inhibitor = nullptr;
		}
		d->active = false;
		return;
	}

	if (!d->display || !d->seat || !d->surface) return;

	if (!d->manager) {
		d->registry = wl_display_get_registry(d->display);
		wl_registry_add_listener(d->registry, &registryListener, d);
		wl_display_roundtrip(d->display);
	}
	if (!d->manager) return;

	if (!d->inhibitor) {
		d->inhibitor = zwp_keyboard_shortcuts_inhibit_manager_v1_inhibit_shortcuts(d->manager, d->surface, d->seat);
		if (d->inhibitor) zwp_keyboard_shortcuts_inhibitor_v1_add_listener(d->inhibitor, &inhibitorListener, d);
	}
}

bool WaylandInhibitor::active() const {
	return d->active;
}
