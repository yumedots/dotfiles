pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Reads the global cursor position from the fifo the agent-cursor Hyprland
// plugin writes. Valid stays false until the first position arrives.
QtObject {
	id: root

	// Global cursor position in layout coordinates.
	property real x: 0
	property real y: 0
	property bool valid: false

	readonly property string fifoPath: Agent.cursorFifoPath({
		XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR"),
		HYPRLAND_INSTANCE_SIGNATURE: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
	})

	property Process reader: Process {
		command: ["cat", root.fifoPath]

		stdout: SplitParser {
			splitMarker: "\n"

			onRead: function (data) {
				const parts = String(data).trim().split(/\s+/);

				if (parts.length < 2)
					return;

				const nextX = parseFloat(parts[0]);
				const nextY = parseFloat(parts[1]);

				if (isNaN(nextX) || isNaN(nextY))
					return;

				root.x = nextX;
				root.y = nextY;
				root.valid = true;
			}
		}

		onExited: root.retry.restart()
	}

	property Timer retry: Timer {
		interval: 1000
		onTriggered: root.reader.running = true
	}

	Component.onCompleted: root.reader.running = true
}
