import QtQuick
import Quickshell
import Quickshell.Io
import qs
import "bar"
import "dock"
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
	}

	Variants {
		model: Quickshell.screens

		Bar {}
	}

	Dock {
		visible: Config.dockEnabled
		onLauncherRequested: launcherWindow.toggle()
	}

	Launcher {
		id: launcherWindow
	}
}
