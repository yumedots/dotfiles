//@ pragma IconTheme breeze
import QtQuick
import qs
import qs.services
import Quickshell
import Quickshell.Io
import "launcher"

Root {
	id: launcherRoot
	role: "launcher"

	property bool linked: false

	Socket {
		id: link
		path: Quickshell.env("QS_MAIN_SOCK") || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-main-" + Quickshell.instanceId + ".sock")

		Component.onCompleted: connected = true

		onConnectionStateChanged: {
			if (connected) {
				launcherRoot.linked = true;
				relink.stop();
				return;
			}

			if (!launcherRoot.linked)
				return;

			launcherRoot.linked = false;
			relink.start();
		}

		onError: {
			if (!launcherRoot.linked && !relink.running)
				Qt.quit();
		}
	}

	Timer {
		id: relink
		interval: 200

		onTriggered: if (!link.connected)
			link.connected = true;
	}

	function takeWake() {
		if (Yudae.connected)
			Yudae.cmd("launcher", { takeWake: true });
	}

	Connections {
		target: Yudae

		function onConnectedChanged() {
			launcherRoot.takeWake();
		}
	}

	Component.onCompleted: launcherRoot.takeWake()
}
