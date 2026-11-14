#ifndef NOTIFYBUS_H
#define NOTIFYBUS_H

#include <stdint.h>

#define NB_MAX_ACTIONS 32

typedef struct {
	const char *app;
	const char *icon;
	const char *summary;
	const char *body;
	const char *desktop;
	const char *image_path;
	const uint8_t *image_data;
	uint32_t image_size;
	int32_t image_width;
	int32_t image_height;
	int32_t image_stride;
	int32_t image_channels;
	int32_t image_alpha;
	uint32_t replaces;
	int32_t urgency;
	int32_t timeout;
	int32_t pid;
	int32_t action_count;
	const char *actions[NB_MAX_ACTIONS];
} nb_note;

typedef uint32_t (*nb_notify_fn)(void *ctx, const nb_note *note);
typedef void (*nb_close_fn)(void *ctx, uint32_t id);

int nb_run(void *ctx, nb_notify_fn notify, nb_close_fn close_fn);
void nb_emit_closed(uint32_t id, uint32_t reason);
void nb_emit_action(uint32_t id, const char *key);

#endif
