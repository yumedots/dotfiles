pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs

QtObject {
	id: root

	signal arrived(var notification)
	signal changed()

	property var list: []
	property int nextId: 0

	property NotificationServer server: NotificationServer {
		keepOnReload: true
		bodySupported: true
		bodyMarkupSupported: true
		bodyHyperlinksSupported: true
		imageSupported: true
		actionsSupported: true

		onNotification: function (notification) {
			const row = root.rowOf(notification);

			notification.closed.connect(function () {
				root.markGone(row.id);
			});

			root.list = root.list.concat([row]).slice(-Config.notifyHistory);
			root.changed();
			root.arrived(notification);
		}
	}

	readonly property int count: root.list.length
	readonly property bool empty: root.count === 0
	readonly property var latest: root.count > 0 ? root.list[root.count - 1] : null

	function rowOf(notification) {
		root.nextId += 1;

		return {
			id: root.nextId,
			appName: notification.appName || "",
			summary: notification.summary || "",
			body: notification.body || "",
			image: notification.image || "",
			icon: notification.appIcon || "",
			desktopEntry: notification.desktopEntry || "",
			urgent: notification.urgency === NotificationUrgency.Critical,
			gone: false,
			notification: notification
		};
	}

	function alive(row) {
		return !!row && !!row.notification && typeof row.notification.dismiss === "function";
	}

	function markGone(id) {
		let touched = false;

		const next = root.list.map(function (row) {
			if (row.id !== id)
				return row;

			touched = true;
			return Object.assign({}, row, { gone: true });
		});

		if (!touched)
			return;

		root.list = next;
		root.changed();
	}

	function remove(row) {
		root.list = root.list.filter(function (item) {
			return item.id !== row.id;
		});
		root.changed();
	}

	function dismiss(row) {
		if (!row)
			return;

		if (root.alive(row))
			row.notification.dismiss();

		root.remove(row);
	}

	function dismissAll() {
		root.list.slice().forEach(root.dismiss);
	}
}
