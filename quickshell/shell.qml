import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.ui
import "bar"
import "launcher"

ShellRoot {
	id: shellRoot

	function closeWidgets() {
		if (bars.instances.length > 0)
			bars.instances[0].closePopups(null);
	}

	function closeWidgetsUnderLauncher() {
		if (launcherWindow.shown)
			shellRoot.closeWidgets();
	}

	function closeLauncherUnderWidget() {
		if (!launcherWindow.shown)
			return;

		let open = false;

		if (bars.instances.length > 0)
			open = bars.instances[0].anyPopupOpen();

		if (open)
			launcherWindow.close();
	}

	function openWidget(id, keyboard) {
		if (bars.instances.length > 0)
			bars.instances[0].toggleWidget(id, keyboard);

		if (launcherWindow.shown)
			Handoff.run(shellRoot.closeLauncherUnderWidget);
	}

	IpcHandler {
		target: "shell"

		function launcher() {
			const wasOpen = launcherWindow.shown;

			launcherWindow.toggle();

			if (!wasOpen)
				Handoff.run(shellRoot.closeWidgetsUnderLauncher);
		}

		function windows() {
			const wasOpen = launcherWindow.shown;

			launcherWindow.toggleWindows();

			if (!wasOpen)
				Handoff.run(shellRoot.closeWidgetsUnderLauncher);
		}

		function cpu() {
			shellRoot.openWidget("cpu", false);
		}

		function memory() {
			shellRoot.openWidget("memory", false);
		}

		function volume() {
			shellRoot.openWidget("volume", false);
		}

		function calendar() {
			shellRoot.openWidget("clock", true);
		}

		function notifications() {
			shellRoot.openWidget("notify", true);
		}

		function github() {
			shellRoot.openWidget("github", true);
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
