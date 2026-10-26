//@ pragma IconTheme breeze
import QtQuick
import qs
import Quickshell
import Quickshell.Io
import "launcher"

Root {
	id: launcherRoot
	role: "launcher"

	property bool linked: false
	readonly property string mainPid: Quickshell.env("QS_MAIN_PID") || "0"

	FileView {
		id: wake
		path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-launcher-wake"
		preload: true
		blockLoading: true
		printErrors: false
	}

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
			probe.running = true;
		}

		onError: {
			if (!launcherRoot.linked && !probe.running && !relink.running)
				Qt.quit();
		}
	}

	Process {
		id: probe
		command: ["sh", "-c", "kill -0 " + launcherRoot.mainPid]

		onExited: function (exitCode, exitStatus) {
			if (exitCode !== 0) {
				Qt.quit();
				return;
			}

			relink.start();
		}
	}

	Timer {
		id: relink
		interval: 200

		onTriggered: if (!link.connected)
			link.connected = true;
	}

	Component.onCompleted: {
		const action = (wake.text() || "").trim();

		if (action === "launcher")
			launcher();
		else if (action === "windows")
			windowSwitcher();
		else if (action === "clipboard")
			clipboard();
		else if (action === "powerMenu")
			powerMenu();

		if (action)
			Quickshell.execDetached(["rm", wake.path]);
	}
}
