import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "config.js" as Config
import "helpers.js" as Helpers

PanelWindow {
	id: root

	property bool mapped: false
	property bool shown: false
	property string query: ""
	property int index: 0
	property point hoverScene: Qt.point(-1, -1)
	property var pins: []
	property var usage: ({})
	property var files: []
	property var clips: []
	property bool windows: false

	readonly property var prefix: Helpers.detectPrefix(root.query, Config.launcherMarks)
	readonly property string search: root.windows ? root.query : root.prefix.text
	readonly property string mode: root.windows ? "windows" : root.prefix.mode
	readonly property string home: Quickshell.env("HOME")
	readonly property string stateDir: Quickshell.shellDir + "/cache/launcher"
	readonly property var results: root.buildResults()
	readonly property int listHeight: Config.launcherMaxRows * Config.launcherRowHeight
	readonly property string modeGlyph: root.mode === "files" ? Config.launcherIconFiles : Config.launcherIconClipboard
	readonly property string prompt: root.mode === "" || root.mode === "windows" ? Config.launcherPrompt : root.modeGlyph

	anchors.top: true
	anchors.bottom: true
	anchors.left: true
	anchors.right: true

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "launcher"
	WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
	WlrLayershell.focusable: true

	exclusiveZone: 0
	color: "transparent"
	visible: root.mapped

	function open() {
		root.query = "";
		root.index = 0;
		root.mapped = true;
		root.files = [];
		root.clips = [];
		Hyprland.refreshToplevels();
		pinsFile.running = true;
		usageFile.running = true;
		Qt.callLater(function () {
			root.shown = true;
			input.forceActiveFocus();
		});
	}

	function openWindows() {
		root.windows = true;
		root.open();
	}

	function close() {
		root.shown = false;
		root.mapped = false;
		root.query = "";
		findTimer.stop();
		findFiles.running = false;
	}

	function toggle() {
		if (root.shown)
			root.close();
		else {
			root.windows = false;
			root.open();
		}
	}

	function toggleWindows() {
		if (root.shown && root.windows)
			root.close();
		else
			root.openWindows();
	}

	function commandEntries() {
		return Config.launcherCommands.map(function (item) {
			return {
				id: "cmd:" + item.name,
				kind: "command",
				name: item.name,
				keywords: item.keywords || [],
				command: item.command
			};
		});
	}

	function actionEntries() {
		return Config.launcherActions.map(function (item) {
			return {
				id: "act:" + item.name,
				kind: "action",
				name: item.name,
				keywords: ["power", "session"],
				command: item.command,
				glyph: item.glyph
			};
		});
	}

	function windowEntries() {
		const values = Hyprland.toplevels.values ? Hyprland.toplevels.values : [];

		return values.map(function (toplevel) {
			const info = toplevel.lastIpcObject ? toplevel.lastIpcObject : {};
			const candidates = Helpers.windowAppCandidates(toplevel, Config.dockTerminalClasses);
			const appId = candidates.word && appIcons.iconOf(candidates.word) ? candidates.word : candidates.className;

			return {
				id: "win:" + toplevel.address,
				kind: "window",
				name: info.title || candidates.className,
				appId: appId,
				keywords: [candidates.className],
				address: toplevel.address,
				focus: info.focusHistoryID === undefined ? 999 : info.focusHistoryID
			};
		}).sort(function (a, b) {
			return a.focus - b.focus;
		});
	}

	function allEntries() {
		return root.actionEntries().concat(root.commandEntries()).concat(Helpers.appEntries(appIcons.entries, Config.launcherIgnoreApps));
	}

	function buildResults() {
		if (root.mode === "files")
			return root.files;

		if (root.mode === "clipboard")
			return root.clips;

		if (root.mode === "windows")
			return root.search === "" ? root.windowEntries() : Helpers.rankEntries(root.windowEntries(), root.search, [], {});

		const ranked = Helpers.rankEntries(root.allEntries(), root.search, root.pins, root.usage);
		const calc = Helpers.calcEntry(root.search);

		return calc === null ? ranked : [calc].concat(ranked);
	}

	function rowGlyph(entry) {
		if (!entry)
			return "";

		if (entry.kind === "command")
			return Config.launcherIconCommand;
		if (entry.kind === "action")
			return entry.glyph;
		if (entry.kind === "window")
			return Config.launcherIconWindow;
		if (entry.kind === "file")
			return Config.launcherIconFile;
		if (entry.kind === "clip")
			return Config.launcherIconClipboard;

		return Config.launcherIconCalc;
	}

	function emptyText() {
		if (root.mode === "files")
			return "Type two letters or more to search " + root.home;
		if (root.mode === "clipboard")
			return "Nothing copied yet";
		if (root.mode === "windows")
			return "No windows open";

		return "Nothing matches";
	}

	function move(step) {
		const last = root.results.length - 1;

		if (last < 0)
			return;

		root.index = Math.max(0, Math.min(last, root.index + step));
		list.positionViewAtIndex(root.index, ListView.Contain);
	}

	function writeFile(path, text) {
		Quickshell.execDetached(["sh", "-c", "mkdir -p " + Helpers.shellQuote(root.stateDir)
			+ " && printf '%s' " + Helpers.shellQuote(text) + " > " + Helpers.shellQuote(path)]);
	}

	function remember(entry) {
		if (!entry || entry.kind === "calc" || entry.kind === "file" || entry.kind === "clip" || entry.kind === "window")
			return;

		root.usage = Helpers.bumpUsage(root.usage, entry.id, Date.now());
		root.writeFile(root.stateDir + "/usage.txt", Helpers.formatUsage(root.usage, Config.launcherUsageMax));
	}

	function pin(entry) {
		if (!entry || entry.kind === "calc" || entry.kind === "file" || entry.kind === "clip" || entry.kind === "window")
			return;

		root.pins = Helpers.togglePin(root.pins, entry.id);
		root.writeFile(root.stateDir + "/pins.txt", root.pins.join("\n"));
	}

	function copy(text) {
		Quickshell.execDetached(["sh", "-c", "printf '%s' " + Helpers.shellQuote(text) + " | wl-copy"]);
	}

	function focusWindow(address) {
		const target = address.indexOf("0x") === 0 ? address : "0x" + address;

		Hyprland.dispatch(Hyprland.usingLua
			? "hl.dsp.focus({ window = \"address:" + target + "\" })"
			: "focuswindow address:" + target);
	}

	function activate(entry) {
		if (!entry)
			return;

		if (entry.kind === "app")
			Quickshell.execDetached(Helpers.launchCommand(entry, entry.appId));
		else if (entry.kind === "window")
			root.focusWindow(entry.address);
		else if (entry.kind === "command" || entry.kind === "action")
			Quickshell.execDetached(["sh", "-c", entry.command]);
		else if (entry.kind === "calc")
			root.copy(entry.value);
		else if (entry.kind === "clip")
			Quickshell.execDetached(["sh", "-c", "cliphist decode " + Helpers.shellQuote(entry.clipId) + " | wl-copy"]);
		else if (entry.kind === "file")
			Quickshell.execDetached(["xdg-open", entry.path]);

		root.remember(entry);
		root.close();
	}

	onSearchChanged: {
		if (root.mode !== "files") {
			findTimer.stop();
			root.files = [];
			return;
		}

		if (root.search.length < 2) {
			root.files = [];
			findTimer.stop();
			return;
		}

		findTimer.restart();
	}

	onModeChanged: {
		if (root.mode === "clipboard")
			clipsList.running = true;
	}

	onResultsChanged: root.index = Math.max(0, Math.min(root.index, root.results.length - 1))

	AppIcons {
		id: appIcons
	}

	Process {
		id: pinsFile

		command: ["sh", "-c", "cat " + Helpers.shellQuote(root.stateDir + "/pins.txt") + " 2>/dev/null"]

		stdout: StdioCollector {
			onStreamFinished: root.pins = Helpers.pinnedFromText(text)
		}
	}

	Process {
		id: usageFile

		command: ["sh", "-c", "cat " + Helpers.shellQuote(root.stateDir + "/usage.txt") + " 2>/dev/null"]

		stdout: StdioCollector {
			onStreamFinished: root.usage = Helpers.parseUsage(text)
		}
	}

	Process {
		id: clipsList

		command: ["sh", "-c", "cliphist list 2>/dev/null | head -n " + Config.launcherMaxResults]

		stdout: StdioCollector {
			onStreamFinished: root.clips = Helpers.parseClipboardList(text).map(function (entry) {
				return {
					id: "clip:" + entry.id,
					kind: "clip",
					name: entry.text,
					keywords: [],
					clipId: entry.id
				};
			})
		}
	}

	Process {
		id: findFiles

		command: Helpers.fileSearchCommand(root.home, root.search, Config.launcherFileDepth, Config.launcherFileMax, Config.launcherFileSkip)

		stdout: StdioCollector {
			onStreamFinished: root.files = Helpers.pathLines(text).map(function (path) {
				return { id: "file:" + path, kind: "file", name: path, keywords: [], path: path };
			})
		}
	}

	Timer {
		id: findTimer

		interval: Config.launcherFileDebounce

		onTriggered: {
			findFiles.running = false;
			findFiles.running = true;
		}
	}

	MouseArea {
		anchors.fill: parent
		onClicked: root.close()
	}

	HyprBorder {
		id: card

		anchors.centerIn: parent

		width: Config.launcherWidth
		height: column.implicitHeight + card.inset * 2
		padding: Config.launcherPadding
		backgroundColor: Config.surfaceTranslucent
		opacity: root.shown ? 1 : 0
		borderOpacity: Math.pow(opacity, 8)

		Behavior on opacity {
			NumberAnimation { duration: card.appearDuration; easing.type: Easing.OutCubic }
		}

		Column {
			id: column

			width: parent.width
			spacing: Config.launcherGap

			Rectangle {
				width: parent.width
				height: Config.launcherInputHeight
				color: Config.launcherSearchBox

				Text {
					id: fieldGlyph

					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					width: Config.launcherIconSlot
					horizontalAlignment: Text.AlignHCenter
					font.family: Config.fontFamily
					font.pixelSize: Config.launcherIconSize
					color: Config.foreground
					text: root.prompt
				}

				TextInput {
					id: input

					anchors.left: fieldGlyph.right
					anchors.leftMargin: Config.launcherTextGap
					anchors.right: parent.right
					anchors.rightMargin: Config.launcherTextGap
					anchors.verticalCenter: parent.verticalCenter
					focus: root.shown
					clip: true
					selectByMouse: true
					color: Config.foreground
					font.family: Config.fontFamily
					font.pixelSize: Config.launcherFontSize
					text: root.query

					onTextChanged: {
						root.query = text;
						root.index = 0;
					}

					Keys.onDownPressed: root.move(1)
					Keys.onUpPressed: root.move(-1)
					Keys.onReturnPressed: root.activate(root.results[root.index])
					Keys.onEnterPressed: root.activate(root.results[root.index])
					Keys.onEscapePressed: root.close()
					Keys.onPressed: (event) => {
						if (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier) {
							root.pin(root.results[root.index]);
							event.accepted = true;
						} else if (event.key === Qt.Key_PageDown) {
							root.move(Config.launcherMaxRows);
							event.accepted = true;
						} else if (event.key === Qt.Key_PageUp) {
							root.move(-Config.launcherMaxRows);
							event.accepted = true;
						}
					}
				}

				Text {
					anchors.left: input.left
					anchors.right: input.right
					anchors.verticalCenter: parent.verticalCenter
					elide: Text.ElideRight
					visible: input.text === ""
					font.family: Config.fontFamily
					font.pixelSize: Config.launcherFontSize
					color: Config.muted
					text: "Type to search..."
				}
			}

			ListView {
				id: list

				width: column.width
				height: root.listHeight
				visible: root.results.length > 0
				model: root.results
				currentIndex: root.index
				clip: true
				interactive: false
				boundsBehavior: Flickable.StopAtBounds

				WheelHandler {
					onWheel: (event) => {
						const last = Math.max(0, list.contentHeight - list.height);

						list.contentY = Math.max(0, Math.min(last, list.contentY - event.angleDelta.y / 2));
						event.accepted = true;
					}
				}

				delegate: Item {
					id: row

					required property var modelData
					required property int index

					width: list.width
					height: Config.launcherRowHeight

					readonly property bool active: row.index === root.index
					readonly property bool pinned: root.pins.indexOf(row.modelData.id) >= 0

					Rectangle {
						anchors.fill: parent
						color: row.active ? Config.launcherHighlight : "transparent"
					}

					Item {
						id: rowIcon

						anchors.left: parent.left
						anchors.verticalCenter: parent.verticalCenter
						width: Config.launcherIconSlot
						height: Config.launcherIconSlot

						IconImage {
							anchors.centerIn: parent
							implicitSize: Config.launcherIconSize
							visible: row.modelData.appId !== undefined && row.modelData.appId !== ""
							source: row.modelData.appId !== undefined && row.modelData.appId !== "" ? appIcons.iconOf(row.modelData.appId) : ""
						}

						Text {
							anchors.centerIn: parent
							visible: row.modelData.appId === undefined || row.modelData.appId === ""
							font.family: Config.fontFamily
							font.pixelSize: Config.launcherIconSize
							color: row.active ? Config.launcherHighlightText : Config.foreground
							text: root.rowGlyph(row.modelData)
						}
					}

					Text {
						anchors.left: rowIcon.right
						anchors.leftMargin: Config.launcherTextGap
						anchors.right: rowPin.left
						anchors.rightMargin: Config.launcherTextGap
						anchors.verticalCenter: parent.verticalCenter
						elide: Text.ElideRight
						font.family: Config.fontFamily
						font.pixelSize: Config.launcherFontSize
						color: row.active ? Config.launcherHighlightText : Config.foreground
						text: row.modelData.name
					}

					Text {
						id: rowPin

						anchors.right: parent.right
						anchors.rightMargin: Config.launcherPadding
						anchors.verticalCenter: parent.verticalCenter
						visible: row.pinned
						font.family: Config.fontFamily
					font.pixelSize: Config.launcherIconSize
					color: row.active ? Config.launcherHighlightText : Config.dim
						text: Config.launcherIconPin
					}

					MouseArea {
						anchors.fill: parent
						hoverEnabled: true

						onPositionChanged: (mouse) => {
							const scene = row.mapToItem(null, mouse.x, mouse.y);
							const moved = scene.x !== root.hoverScene.x || scene.y !== root.hoverScene.y;

							root.hoverScene = scene;

							if (moved)
								root.index = row.index;
						}
						onClicked: root.activate(row.modelData)
					}
				}
			}

			Item {
				width: parent.width
				height: root.listHeight
				visible: root.results.length === 0

				Text {
					anchors.left: parent.left
					anchors.right: parent.right
					anchors.leftMargin: Config.launcherPadding
					anchors.rightMargin: Config.launcherPadding
					anchors.verticalCenter: parent.verticalCenter
					horizontalAlignment: Text.AlignHCenter
					elide: Text.ElideRight
					font.family: Config.fontFamily
					font.pixelSize: Config.launcherFontSize
					color: Config.muted
					text: root.emptyText()
				}
			}
		}
	}
}
