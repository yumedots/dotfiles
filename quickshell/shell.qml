//@ pragma IconTheme breeze
pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import Quickshell
import Quickshell.Io

Root {
	id: mainShell

	readonly property string linkPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-main-" + Quickshell.instanceId + ".sock"

	function spawnLauncher() {
		Yudae.cmd("launcher", { wake: { sock: mainShell.linkPath, pid: Quickshell.processId, path: mainShell.launcherPath } });
	}

	Component.onCompleted: mainShell.spawnLauncher()

	Connections {
		target: Yudae

		function onConnectedChanged() {
			if (Yudae.connected)
				mainShell.spawnLauncher();
		}
	}

	SocketServer {
		active: true
		path: mainShell.linkPath

		handler: Socket {
			onConnectionStateChanged: {
				if (connected) {
					relaunch.stop();
					return;
				}

				relaunch.tries = 0;
				relaunch.start();
			}
		}
	}

	Timer {
		id: relaunch
		property int tries: 0
		interval: 300
		repeat: true

		onTriggered: {
			relaunch.tries += 1;

			if (relaunch.tries > 5) {
				relaunch.stop();
				return;
			}

			mainShell.spawnLauncher();
		}
	}
}
