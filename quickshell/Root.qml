import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.ui
import "bar"
import "launcher"

ShellRoot {
	id: shellRoot

	property string role: "main"
	property double hyprBootAt: Date.now()
	readonly property bool isLauncher: role === "launcher"

	function toLauncher(fn, arg) {
		const cmd = ["quickshell", "ipc", "-p", Quickshell.env("HOME") + "/.config/quickshell/launcherShell.qml", "call", "shell", fn];

		if (arg !== undefined && arg !== null)
			cmd.push(arg);

		Quickshell.execDetached(cmd);
	}

	function toMain(fn) {
		Quickshell.execDetached(["quickshell", "ipc", "call", "shell", fn]);
	}

	function launcher() {
		if (!shellRoot.isLauncher) {
			shellRoot.toLauncher("launcher");
			return;
		}

		const wasOpen = launcherWindow.shown;

		launcherWindow.toggle();

		if (!wasOpen)
			Handoff.run(shellRoot.closeWidgetsUnderLauncher);
	}

	function windowSwitcher() {
		if (!shellRoot.isLauncher) {
			shellRoot.toLauncher("windows");
			return;
		}

		if (launcherWindow.shown && launcherWindow.windows) {
			launcherWindow.stepWindows(1);
			return;
		}

		const wasOpen = launcherWindow.shown;

		launcherWindow.openWindows();

		if (!wasOpen)
			Handoff.run(shellRoot.closeWidgetsUnderLauncher);
	}

	function closeWidgets() {
		if (bars.instances.length > 0)
			bars.instances[0].closePopups(null);
	}

	function closeWidgetsUnderLauncher() {
		if (shellRoot.isLauncher) {
			shellRoot.toMain("closeBarPopups");
			return;
		}

		if (launcherWindow.shown)
			shellRoot.closeWidgets();
	}

	function closeLauncherUnderWidget() {
		if (!shellRoot.isLauncher) {
			shellRoot.toLauncher("closeLauncher");
			return;
		}

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

	function media(action) {
		const command = Media.command(Mpris.players.values ? Mpris.players.values : [], action);

		if (command.length > 0)
			Quickshell.execDetached(command);
	}

	Instantiator {
		model: shellRoot.isLauncher ? [["launcher", "launcher"], ["windows", "windows"]] : []

		delegate: GlobalShortcut {
			required property var modelData

			name: modelData[0]

			onPressed: modelData[1] === "launcher" ? shellRoot.launcher() : shellRoot.windowSwitcher()
		}
	}

	Instantiator {
		model: shellRoot.isLauncher ? [] : [["cpu", "cpu"], ["memory", "memory"], ["volume", "volume"], ["calendar", "clock"], ["notifications", "notify"], ["contributions", "github"], ["media", "media"], ["display", "display"]]

		delegate: GlobalShortcut {
			required property var modelData

			name: modelData[0]

			onPressed: shellRoot.openWidget(modelData[1], true)
		}
	}

	Instantiator {
		model: shellRoot.isLauncher ? [] : ["playPause", "next", "previous"]

		delegate: GlobalShortcut {
			required property string modelData

			name: "media" + modelData.charAt(0).toUpperCase() + modelData.slice(1)

			onPressed: shellRoot.media(modelData)
		}
	}

	IpcHandler {
		target: "shell"

		function launcher() {
			shellRoot.launcher();
		}

		function windows() {
			shellRoot.windowSwitcher();
		}

		function windowsStep(direction: string) {
			if (!shellRoot.isLauncher) {
				shellRoot.toLauncher("windowsStep", direction);
				return;
			}

			launcherWindow.stepWindows({ left: -1, right: 1, up: -launcherWindow.windowColumns, down: launcherWindow.windowColumns }[direction] || 0);
		}

		function cpu() {
			shellRoot.openWidget("cpu", true);
		}

		function memory() {
			shellRoot.openWidget("memory", true);
		}

		function volume() {
			shellRoot.openWidget("volume", true);
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

		function media() {
			shellRoot.openWidget("media", true);
		}

		function killPopups() {
			if (shellRoot.isLauncher) {
				launcherWindow.close();
				return;
			}

			shellRoot.closeWidgets();
			shellRoot.toLauncher("killPopupsLocal");
		}

		function killPopupsLocal() {
			launcherWindow.close();
		}

		function closeBarPopups() {
			shellRoot.closeWidgets();
		}

		function closeLauncher() {
			launcherWindow.close();
		}

		function display() {
			shellRoot.openWidget("display", true);
		}
	}

	Connections {
		target: Hyprland

		function onActiveToplevelChanged() {
			if (Date.now() - shellRoot.hyprBootAt < 1000)
				return;

			if (!Hyprland.activeToplevel)
				return;

			shellRoot.closeWidgets();
			launcherWindow.close();
		}

		function onFocusedWorkspaceChanged() {
			if (Date.now() - shellRoot.hyprBootAt < 1000)
				return;

			shellRoot.closeWidgets();
			launcherWindow.close();
		}
	}

	Variants {
		id: bars

		model: shellRoot.isLauncher ? [] : Quickshell.screens

		Bar {
			onWidgetActivated: Handoff.run(shellRoot.closeLauncherUnderWidget)
		}
	}

	Launcher {
		id: launcherWindow
	}
}
