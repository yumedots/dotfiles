import QtQuick
import Quickshell
import Quickshell.Io
import "bar"
import "dock"
import "launcher"
import "config.js" as Config

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
