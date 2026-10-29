#ifndef TRAYBUS_H
#define TRAYBUS_H

#include <stdint.h>

typedef struct {
	const char *key;
	const char *id;
	const char *title;
	const char *icon_name;
	const char *theme_path;
	const char *status;
	const char *menu_json;
	int32_t has_menu;
	int32_t item_is_menu;
	int32_t pixmap_width;
	int32_t pixmap_height;
	uint32_t pixmap_size;
	const uint8_t *pixmap;
} tb_item;

typedef void (*tb_update_fn)(void *ctx, const tb_item *items, int32_t count);

int tb_run(void *ctx, tb_update_fn update);
void tb_activate(const char *key, int32_t kind);
void tb_menu_event(const char *key, int32_t id);
void tb_menu_open(const char *key);

#endif
