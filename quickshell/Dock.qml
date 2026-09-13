import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import "config.js" as Config
import "helpers.js" as Helpers

PanelWindow {
	id: dock

	anchors.bottom: true
	margins.bottom: Config.dockBottomMargin
	color: "transparent"

	implicitWidth: plate.width
	implicitHeight: plate.height
	exclusiveZone: plate.height + Config.dockGap

	readonly property int pool: 16
	readonly property var windowEvents: ["openwindow", "closewindow", "movewindow", "changefloatingmode", "windowtitle"]
	property bool launcherOpen: false
	readonly property var toplevels: Hyprland.toplevels.values
	readonly property string activeAddress: Hyprland.activeToplevel ? Hyprland.activeToplevel.address : ""
	readonly property int workspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
	property var applications: ({})
	property var icons: ({})
	property var apps: []
	property string menuAppId: ""
	property real menuX: 0
	property real menuY: 0

	function classOf(toplevel) {
		return toplevel.lastIpcObject.class || "";
	}

	function appIdOf(toplevel) {
		const cls = dock.classOf(toplevel);
		const word = Helpers.terminalAppId(cls, toplevel.lastIpcObject ? toplevel.lastIpcObject.title : "", Config.dockTerminalClasses);

		return word && dock.iconOf(word) ? word : cls;
	}

	function windowsOf(appId) {
		if (!appId)
			return [];

		return Helpers.orderedWindows(dock.toplevels.filter(function (toplevel) {
			return dock.appIdOf(toplevel).toLowerCase() === appId.toLowerCase();
		}), dock.workspaceId);
	}


	function entryOf(appId) {
		return Helpers.lookupApp(dock.applications, appId);
	}

	function iconOf(appId) {
		if (!appId)
			return "";

		if (dock.icons[appId])
			return dock.icons[appId];

		const entry = dock.entryOf(appId);
		const candidates = [entry ? entry.icon : "", appId, Config.dockFallbackIcon];

		for (let i = 0; i < candidates.length; i++) {
			if (candidates[i] && Quickshell.hasThemeIcon(candidates[i])) {
				dock.icons[appId] = Quickshell.iconPath(candidates[i], true);
				return dock.icons[appId];
			}
		}

		return "";
	}

	function computeApps() {
		const ids = Config.dockPinned.slice();

		dock.toplevels.forEach(function (toplevel) {
			const appId = dock.appIdOf(toplevel);

			if (appId && !ids.some(function (id) { return id.toLowerCase() === appId.toLowerCase(); }))
				ids.push(appId);
		});

		dock.apps = ids.map(function (id) {
			return { id: id, icon: dock.iconOf(id), windows: dock.windowsOf(id) };
		});
	}

	function focus(toplevel) {
		const address = toplevel.address.indexOf("0x") === 0 ? toplevel.address : "0x" + toplevel.address;

		Hyprland.dispatch(Hyprland.usingLua
			? "hl.dsp.focus({ window = \"address:" + address + "\" })"
			: "focuswindow address:" + address);
	}

	function activate(appId) {
		const windows = dock.windowsOf(appId);

		if (windows.length > 0) {
			dock.focus(windows[Helpers.nextIndex(windows.map(function (toplevel) { return toplevel.address; }), dock.activeAddress)]);
			return;
		}

		const entry = dock.entryOf(appId);

		Quickshell.execDetached(Helpers.launchCommand(entry, appId));
	}

	function toggleLauncher() {
		if (dock.launcherOpen) {
			Quickshell.execDetached(["pkill", "-x", Config.dockLauncherProcess]);
			dock.launcherOpen = false;
			return;
		}

		Quickshell.execDetached(Config.dockLauncherCommand);
		dock.launcherOpen = true;
	}

	function isPinned(appId) {
		return Config.dockPinned.some(function (id) { return id.toLowerCase() === appId.toLowerCase(); });
	}

	function togglePin(appId) {
		Helpers.togglePin(Config.dockPinned, appId);
		dock.writeConfigPins();
		dock.computeApps();
		dock.closeMenu();
	}

	function writeConfigPins() {
		const pins = Config.dockPinned.map(function (id) { return "\"" + id.replace(/[\"\\]/g, "") + "\""; }).join(", ");

		Quickshell.execDetached(["sh", "-c", "sed -i 's|^const dockPinned = .*$|const dockPinned = [" + pins + "]|' \"$HOME/.config/quickshell/config.js\""]);
	}

	function writePins() {
		const args = dock.pinned.map(Helpers.shellQuote).join(" ");

		Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.local/share/quickshell\" && printf '%s\\n' " + args + " > \"$HOME/.local/share/quickshell/dock-pinned.txt\""]);
	}

	function closeWindowApp(appId) {
		const windows = dock.windowsOf(appId);

		if (!windows.length)
			return;

		let target = windows[0];

		for (let i = 0; i < windows.length; i++) {
			if (windows[i].address === dock.activeAddress) {
				target = windows[i];
				break;
			}
		}

		dock.close(target);
		dock.closeMenu();
	}

	function quitApp(appId) {
		dock.windowsOf(appId).forEach(function (toplevel) { dock.close(toplevel); });
		dock.closeMenu();
	}

	function close(toplevel) {
		const address = toplevel.address.indexOf("0x") === 0 ? toplevel.address : "0x" + toplevel.address;

		Hyprland.dispatch(Hyprland.usingLua
			? "hl.dsp.close({ window = \"address:" + address + "\" })"
			: "closewindow address:" + address);
	}

	function openMenu(item) {
		const px = plate.x + row.x + item.x + item.width / 2;
		const py = plate.y + row.y + item.y;

		dock.menuX = Math.max(0, Math.round(px - menu.implicitWidth / 2));
		dock.menuY = Math.round(py - menu.implicitHeight - Config.dockSpacing);
		dock.menuAppId = item.appId;
		menu.visible = true;
	}

	function closeMenu() {
		menu.visible = false;
		dock.menuAppId = "";
	}

	onToplevelsChanged: {
		settle.restart();
		dock.closeMenu();
	}

	onApplicationsChanged: {
		dock.icons = ({});
		dock.computeApps();
	}

	Process {
		id: desktopFiles

		command: ["sh", "-c", "grep -H -E '^(Name|Icon|StartupWMClass|Exec|NoDisplay|Hidden)=' /usr/share/applications/*.desktop \"$HOME/.local/share/applications\"/*.desktop 2>/dev/null"]
		running: true

		stdout: StdioCollector {
			onStreamFinished: dock.applications = Helpers.parseDesktopEntries(text)
		}
	}

	Process {
		id: pinFile

		command: ["sh", "-c", "cat \"$HOME/.local/share/quickshell/dock-pinned.txt\" 2>/dev/null"]
		running: true

		stdout: StdioCollector {
			onStreamFinished: {
				const loaded = Helpers.pinnedFromText(text);

				if (loaded.length) {
					loaded.forEach(function (id) {
						if (!dock.isPinned(id))
							Helpers.togglePin(Config.dockPinned, id);
					});

					dock.computeApps();
				}
			}
		}
	}

	Connections {
		target: Hyprland

		function onRawEvent(event) {
			if (dock.windowEvents.indexOf(event.name) < 0)
				return;

			Hyprland.refreshToplevels();
			settle.restart();
		}
	}

	Timer {
		id: settle

		interval: 150
		running: false
		repeat: false

		onTriggered: dock.computeApps()
	}

	Process {
		id: launcherCheck

		command: ["pgrep", "-x", Config.dockLauncherProcess]
		running: false

		onExited: (code) => {
			dock.launcherOpen = code === 0;
		}
	}

	Timer {
		interval: 400
		running: true
		repeat: true

		onTriggered: launcherCheck.running = true
	}

	Rectangle {
		id: plate

		anchors.horizontalCenter: parent.horizontalCenter
		anchors.bottom: parent.bottom

		width: row.implicitWidth + Config.dockSidePadding * 2
		height: row.implicitHeight + Config.dockBottomPadding + Config.dockTopPadding
		color: Config.background
		radius: Config.dockRadius
	}

	Row {
		id: row

		anchors.horizontalCenter: plate.horizontalCenter
		anchors.bottom: plate.bottom
		anchors.bottomMargin: Config.dockBottomPadding
		spacing: Config.dockSpacing

		Repeater {
			model: dock.pool

			delegate: Item {
				id: item

				required property int index

				readonly property var app: dock.apps[index] === undefined ? null : dock.apps[index]
				readonly property string appId: item.app ? item.app.id : ""
				readonly property var windows: item.app ? item.app.windows : []

				visible: item.appId !== ""
				width: Config.dockIconSize
				height: Config.dockIconSize
				transformOrigin: Item.Center
	opacity: item.appId === "" ? 0 : 1
	scale: item.appId === "" ? Config.dockEnterScale : 1

	Behavior on opacity {
		NumberAnimation { duration: Config.dockEnterDuration; easing.type: Easing.OutCubic }
	}

	Behavior on scale {
		NumberAnimation { duration: Config.dockEnterDuration; easing.type: Easing.OutCubic }
	}


				IconImage {
					anchors.fill: parent
					implicitSize: Config.dockIconSize
					source: item.app ? item.app.icon : ""
				}

				Row {
					anchors.horizontalCenter: parent.horizontalCenter
					anchors.top: parent.bottom
					anchors.topMargin: Config.dockDotGap
					spacing: Config.dockDotSpacing

					Repeater {
						model: Math.min(item.windows.length, Config.dockMaxDots)

						delegate: Rectangle {
							required property int index

							width: Config.dockDotSize
							height: Config.dockDotSize
							radius: Config.dockDotSize / 2
							color: item.windows[index] && item.windows[index].address === dock.activeAddress ? Config.foreground : Config.dim
						}
					}

					Text {
						height: Config.dockDotSize
						verticalAlignment: Text.AlignVCenter
						font.family: Config.fontFamily
						font.pixelSize: Config.dockPlusSize
						color: Config.dim
						text: "+"
						visible: item.windows.length > Config.dockMaxDots
					}
				}

				MouseArea {
					anchors.fill: parent
					acceptedButtons: Qt.LeftButton | Qt.RightButton
					onClicked: (mouse) => {
						if (mouse.button === Qt.RightButton)
							dock.openMenu(item);
						else
							dock.activate(item.appId);
					}
				}
			}
		}

		Rectangle {
			width: Config.dockSeparatorWidth
			height: Config.dockSeparatorHeight
			anchors.verticalCenter: parent.verticalCenter
			color: Config.dockSeparator
		}

		Item {
			id: launcher

			width: Config.dockIconSize
			height: Config.dockIconSize
			anchors.verticalCenter: parent.verticalCenter

			Text {
				anchors.centerIn: parent
				font.family: Config.fontFamily
				font.pixelSize: Config.dockLauncherSize
				color: Config.dockLauncherColor
				text: Config.dockLauncherIcon
			}

			MouseArea {
				anchors.fill: parent
				onPressed: dock.toggleLauncher()
			}
		}
	}

	PopupWindow {
		id: menu

		anchor.window: dock
		anchor.rect.x: dock.menuX
		anchor.rect.y: dock.menuY

		implicitWidth: menuBody.implicitWidth + Config.dockSpacing
		implicitHeight: menuBody.implicitHeight + Config.dockSpacing
		color: "transparent"
		visible: false

		Rectangle {
			anchors.fill: parent
			color: Config.background
			radius: Config.dockRadius
		}

		MouseArea {
			anchors.fill: parent
			onClicked: dock.closeMenu()
		}

		Column {
			id: menuBody

			anchors.fill: parent
			anchors.margins: Config.dockSpacing / 2
			spacing: 2

			Item {
				implicitWidth: pinText.implicitWidth
				implicitHeight: pinText.implicitHeight

				Text {
					id: pinText

					anchors.fill: parent
					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: Config.foreground
					text: dock.isPinned(dock.menuAppId) ? "Unpin from Dock" : "Pin to Dock"
				}

				MouseArea {
					anchors.fill: parent
					onClicked: dock.togglePin(dock.menuAppId)
				}
			}

			Item {
				visible: dock.menuAppId !== "" && dock.windowsOf(dock.menuAppId).length > 0
				implicitWidth: closeText.implicitWidth
				implicitHeight: closeText.implicitHeight

				Text {
					id: closeText

					anchors.fill: parent
					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: Config.foreground
					text: "Close"
				}

				MouseArea {
					anchors.fill: parent
					onClicked: dock.closeWindowApp(dock.menuAppId)
				}
			}

			Item {
				visible: dock.menuAppId !== "" && dock.windowsOf(dock.menuAppId).length > 0
				implicitWidth: quitText.implicitWidth
				implicitHeight: quitText.implicitHeight

				Text {
					id: quitText

					anchors.fill: parent
					font.family: Config.fontFamily
					font.pixelSize: Config.fontSize
					color: Config.foreground
					text: "Quit"
				}

				MouseArea {
					anchors.fill: parent
					onClicked: dock.quitApp(dock.menuAppId)
				}
			}
		}
	}
}
