import QtQuick
import Quickshell
import Quickshell.Io
import qs
import "bar"
import "launcher"

ShellRoot {
	IpcHandler {
		target: "shell"

		function launcher() {
			launcherWindow.toggle();
		}

		function windows() {
			launcherWindow.toggleWindows();
		}

		function cpu() {
			if (bars.instances.length > 0)
				bars.instances[0].toggleWidget("cpu");
		}

		function memory() {
			if (bars.instances.length > 0)
				bars.instances[0].toggleWidget("memory");
		}

		function volume() {
			if (bars.instances.length > 0)
				bars.instances[0].toggleWidget("volume");
		}

		function calendar() {
			if (bars.instances.length > 0)
				bars.instances[0].toggleWidget("date");
		}

		function notifications() {
			if (bars.instances.length > 0)
				bars.instances[0].toggleWidget("notify", true);
		}

		function github() {
			if (bars.instances.length > 0)
				bars.instances[0].toggleWidget("github", true);
		}
	}

	Variants {
		id: bars

		model: Quickshell.screens

		Bar {}
	}

	Launcher {
		id: launcherWindow
	}
}
