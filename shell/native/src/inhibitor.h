#pragma once

struct wl_display;
struct wl_seat;
struct wl_surface;

class WaylandInhibitor {
public:
	struct Private;

	WaylandInhibitor();
	~WaylandInhibitor();

	void setSurface(wl_display *display, wl_seat *seat, wl_surface *surface);
	void inhibit(bool on);
	bool active() const;

private:
	Private *d;
};
