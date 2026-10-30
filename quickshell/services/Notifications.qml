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
		const source = root.source;
		const seq = source.seq || 0;
		const list = source.list || [];

		if (root.seen < 0) {
			root.seen = seq;
			return;
		}

		if (seq === root.seen)
			return;

		root.seen = seq;

		for (let i = 0; i < list.length; i++) {
			if (list[i].id !== source.last)
				continue;

			AppIcons.walkPid(list[i].senderPid);
			root.arrived(list[i]);
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
