pragma Singleton

import QtQuick
import Quickshell
import qs

QtObject {
	id: root

	signal arrived(var notification)

	readonly property var source: Yudae.notifications
	readonly property var list: root.source.list || []
	readonly property int count: root.list.length
	readonly property bool empty: root.count === 0

	property real seen: -1

	function announce() {
		const seq = root.source.seq || 0;

		if (root.seen < 0) {
			root.seen = seq;
			return;
		}

		if (seq === root.seen)
			return;

		root.seen = seq;

		for (let i = 0; i < root.list.length; i++) {
			if (root.list[i].id !== root.source.last)
				continue;

			AppIcons.walkPid(root.list[i].senderPid);
			root.arrived(root.list[i]);
			return;
		}
	}

	onSourceChanged: root.announce()

	function dismiss(row) {
		if (row)
			Yudae.cmd("notify", { dismiss: row.id });
	}

	function dismissAll() {
		Yudae.cmd("notify", { dismissAll: true });
	}

	function invoke(row, key) {
		Yudae.cmd("notify", { invoke: { id: row.id, key: key } });
	}
}
