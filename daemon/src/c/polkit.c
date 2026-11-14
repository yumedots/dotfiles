#include <polkit/polkit.h>
#include <stdio.h>
#include <string.h>

int yudae_polkit_check(int pidfd, int uid, int gid, const char *action, const char *detail, char *error_out, unsigned long error_len) {
	GError *error = NULL;
	PolkitAuthority *authority = polkit_authority_get_sync(NULL, &error);
	if (authority == NULL) {
		snprintf(error_out, error_len, "%s", error ? error->message : "polkit authority unavailable");
		if (error) g_error_free(error);
		return -1;
	}

	GArray *gids = g_array_new(FALSE, FALSE, sizeof(gint));
	g_array_append_val(gids, gid);

	PolkitSubject *subject = polkit_unix_process_new_pidfd(pidfd, uid, gids);
	if (subject == NULL) {
		snprintf(error_out, error_len, "polkit subject unavailable");
		g_array_unref(gids);
		g_object_unref(authority);
		return -1;
	}
	g_array_unref(gids);

	PolkitDetails *details = polkit_details_new();
	if (detail != NULL && detail[0] != '\0') polkit_details_insert(details, "path", detail);

	PolkitAuthorizationResult *result = polkit_authority_check_authorization_sync(
		authority,
		subject,
		action,
		details,
		POLKIT_CHECK_AUTHORIZATION_FLAGS_ALLOW_USER_INTERACTION,
		NULL,
		&error);

	int verdict = -1;
	if (result == NULL) {
		snprintf(error_out, error_len, "%s", error ? error->message : "authorization check failed");
	} else if (polkit_authorization_result_get_is_authorized(result)) {
		verdict = 1;
	} else {
		snprintf(error_out, error_len, "authorization denied");
	}

	if (error) g_error_free(error);
	if (result) g_object_unref(result);
	g_object_unref(details);
	g_object_unref(subject);
	g_object_unref(authority);
	return verdict;
}
