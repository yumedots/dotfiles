pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import "lock"
import "launcher"

ShellRoot {
	id: lockRoot

	readonly property bool preview: Quickshell.env("QS_LOCK_PREVIEW") === "1"
	readonly property string pidFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-lock.pid"

	property string saver: Quickshell.env("QS_LOCK_SAVER") || Config.lockSaver

	function grab() {
		for (let i = 0; i < locks.instances.length; i++)
			locks.instances[i].grab();
	}

	Session {
		id: auth

		preview: lockRoot.preview

		onUnlocked: {
			Quickshell.execDetached(["rm", "-f", lockRoot.pidFile]);
			Qt.quit();
		}
	}

	Variants {
		id: locks

		model: Quickshell.screens

		Stage {
			source: auth
			wallpaper: Yudae.wallpaper.active || ""
			saver: lockRoot.saver

			onPowerRequested: powerMenu.open()
		}
	}

	PowerMenu {
		id: powerMenu

		alwaysMapped: false
	}

	Connections {
		target: powerMenu

		function onShownChanged() {
			if (!powerMenu.shown)
				Qt.callLater(lockRoot.grab);
		}
	}

	IdleMonitor {
		enabled: !lockRoot.preview && Config.lockSleepAfterMinutes > 0
		timeout: Math.max(1, Config.lockSleepAfterMinutes * 60)

		onIsIdleChanged: if (isIdle)
			Quickshell.execDetached(["systemctl", "suspend"])
	}

	IpcHandler {
		target: "lock"

		function screensaver(name: string) {
			lockRoot.saver = name;
		}

		function power() {
			powerMenu.open();
		}
	}
}
