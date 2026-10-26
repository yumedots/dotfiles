//@ pragma IconTheme breeze
pragma ComponentBehavior: Bound

import QtQuick
import qs
import Quickshell
import Quickshell.Io

Root {
	id: mainShell

	readonly property string linkPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-main-" + Quickshell.instanceId + ".sock"

	function spawnLauncher() {
		Quickshell.execDetached(["sh", "-c", "pgrep -f '^quickshell -p " + mainShell.launcherPath + "' >/dev/null || { ulimit -Sn 65536; export MALLOC_ARENA_MAX=2 MALLOC_TRIM_THRESHOLD_=65536 QSG_RENDER_LOOP=basic; setsid env QS_MAIN_SOCK=" + Shell.shellQuote(mainShell.linkPath) + " QS_MAIN_PID=" + Quickshell.processId + " quickshell -p " + Shell.shellQuote(mainShell.launcherPath) + " >/dev/null 2>&1 & echo $! > \"$XDG_RUNTIME_DIR/qs-launcher.pid\"; }"]);
	}

	Component.onCompleted: mainShell.spawnLauncher()

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
