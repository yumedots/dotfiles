import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.ui
import qs.services
import "bar"
import "launcher"
import "wallpaper"

ShellRoot {
	id: shellRoot

	property string role: "main"
	property double hyprBootAt: Date.now()
	readonly property bool isLauncher: role === "launcher"
	readonly property string launcherPath: Quickshell.shellDir + "/launcherShell.qml"

	function toLauncher(fn, arg) {
		Yudae.cmd("route", { to: "launcher", fn: fn, arg: arg === undefined || arg === null ? "" : String(arg) });
	}

	function toMain(fn) {
		Yudae.cmd("route", { to: "main", fn: fn });
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

	function clipboard() {
		if (!shellRoot.isLauncher) {
			shellRoot.toLauncher("clipboard");
			return;
		}

		launcherWindow.openClipboard();
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

		if (Yudae.windows.length === 0)
			return;

		const wasOpen = launcherWindow.shown;

		launcherWindow.openWindows();

		if (!wasOpen)
			Handoff.run(shellRoot.closeWidgetsUnderLauncher);
	}

	function closeBarPopups() {
		if (bars.instances.length > 0)
			bars.instances[0].closePopups(null);
	}

	function closeWidgets() {
		if (wallpaperWindow.shown)
			wallpaperWindow.close();

		shellRoot.closeBarPopups();
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

	function wallpaper() {
		if (shellRoot.isLauncher) {
			shellRoot.toMain("wallpaper");
			return;
		}

		if (wallpaperWindow.shown)
			return;

		wallpaperWindow.open();
		shellRoot.closeBarPopups();
		Handoff.run(shellRoot.closeLauncherUnderWidget);
	}

	function powerMenu() {
		if (powerMenuWindow.shown)
			return;

		powerMenuWindow.open();
		shellRoot.closeBarPopups();
		Handoff.run(shellRoot.closeLauncherUnderWidget);
	}

	function trayGroup() {
		if (bars.instances.length === 0)
			return;

		const tray = bars.instances[0].widgets["tray"];

		if (tray && typeof tray.clicked === "function")
			tray.clicked();
	}

	function speedtest() {
		if (bars.instances.length === 0)
			return;

		const net = bars.instances[0].widgets["network"];

		if (net && typeof net.requestSpeedTest === "function")
			net.requestSpeedTest();
	}

	function bareBar() {

		const all = [];

		for (let i = 0; i < bars.instances.length; i++)
			all.push(bars.instances[i]);

		BarInk.toggleAll(all);
	}

	// Opens a widget, or one of the few things the bar does besides showing
	// widgets.
	function widgetAction(id) {
		if (id === "tray")
			shellRoot.trayGroup();
		else if (id === "speedtest")
			shellRoot.speedtest();
		else if (id === "bareBar")
			shellRoot.bareBar();
		else
			shellRoot.openWidget(id, true);
	}

	function media(action) {
		Yudae.send({ cmd: { media: action } });
	}

	Instantiator {
		model: shellRoot.isLauncher ? [["launcher", "launcher"], ["windows", "windows"], ["powerMenu", "powerMenu"]] : []

		delegate: GlobalShortcut {
			required property var modelData

			name: modelData[0]

			onPressed: modelData[1] === "launcher" ? shellRoot.launcher() : (modelData[1] === "windows" ? shellRoot.windowSwitcher() : shellRoot.powerMenu())
		}
	}

	// The launcher clipboard. The keybind that wakes the launcher sends its
	// shortcut here when the launcher is already running.
	Instantiator {
		model: shellRoot.isLauncher ? [] : [["clipboard", "clipboard"], ["cpu", "cpu"], ["memory", "memory"], ["volume", "volume"], ["calendar", "clock"], ["weather", "weather"], ["notifications", "notify"], ["contributions", "github"], ["media", "media"], ["network", "network"], ["display", "display"], ["power", "power"], ["tray", "tray"], ["bareBar", "bareBar"]]

		delegate: GlobalShortcut {
			required property var modelData

			name: modelData[0]

			onPressed: modelData[1] === "clipboard" ? shellRoot.clipboard() : shellRoot.widgetAction(modelData[1])
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

		function clipboard() {
			shellRoot.clipboard();
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

		function weather() {
			shellRoot.openWidget("weather", true);
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

		function network() {
			shellRoot.openWidget("network", true);
		}

		function speedtest() {
			shellRoot.speedtest();
		}

		function bareBar() {
			shellRoot.bareBar();
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

		function agent() {
			shellRoot.openWidget("agent", true);
		}

		function power() {
			shellRoot.openWidget("power", true);
		}

		function powerMenu() {
			shellRoot.powerMenu();
		}

		function tray() {
			shellRoot.trayGroup();
		}

		function wallpaper() {
			shellRoot.wallpaper();
		}
	}

	property var watchedScripts: []

	function scriptFiles(text) {
		return text.split("\n").map(function (line) {
			return line.trim().split(" ").pop();
		}).filter(function (name) {
			return name.endsWith(".js");
		});
	}

	FileView {
		id: moduleList

		path: Quickshell.shellDir + "/qmldir"
		preload: true
		watchChanges: true

		onFileChanged: Quickshell.reload(false)
		onLoaded: shellRoot.watchedScripts = shellRoot.scriptFiles(moduleList.text())
	}

	Instantiator {
		model: shellRoot.watchedScripts

		delegate: FileView {
			required property string modelData

			path: Quickshell.shellDir + "/" + modelData
			watchChanges: true
			printErrors: false

			onFileChanged: Quickshell.reload(false)
		}
	}

	Connections {
		target: Hyprland

		function onActiveToplevelChanged() {
			if (Date.now() - shellRoot.hyprBootAt < 1000)
				return;

			if (!Hyprland.activeToplevel)
				return;

			if (shellRoot.isLauncher)
				Hyprland.refreshToplevels();

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
		alwaysMapped: shellRoot.isLauncher
		onPowerRequested: shellRoot.powerMenu()
	}

	WallpaperPicker {
		id: wallpaperWindow
		active: !shellRoot.isLauncher
		alwaysMapped: !shellRoot.isLauncher
	}

	PowerMenu {
		id: powerMenuWindow
		alwaysMapped: true
	}
}
