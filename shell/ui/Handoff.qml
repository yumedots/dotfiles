pragma Singleton

import QtQuick
import qs

Item {
	id: root

	property var queue: []

	function run(call) {
		root.queue = root.queue.concat([call]);
		timer.restart();
	}

	Timer {
		id: timer

		interval: Config.popupCloseDelay
		repeat: true

		onTriggered: {
			const calls = root.queue;

			root.queue = [];
			timer.stop();

			calls.forEach(function (call) {
				call();
			});
		}
	}
}
