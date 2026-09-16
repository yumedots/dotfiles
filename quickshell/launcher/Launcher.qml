import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.ui
import qs
import qs.services

PanelWindow {
	id: root

	property bool mapped: false
	property bool shown: false
	property string query: ""
	property var pins: []
	property string terminal: ""
	property var usage: ({})
	property var files: []
	property var clips: []
	property bool windows: false

	readonly property var prefix: Helpers.detectPrefix(root.query, Config.launcherMarks)
	readonly property string search: root.windows ? root.query : root.prefix.text
	readonly property string mode: root.windows ? "windows" : root.prefix.mode
	readonly property string home: Quickshell.env("HOME")
	readonly property string terminalConfig: Config.launcherTerminalConfig.replace("~", root.home)
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
		list.currentIndex = 0;
		root.mapped = true;
		root.files = [];
		root.clips = [];
		Hyprland.refreshToplevels();
		pinsFile.running = true;
		usageFile.running = true;
		terminalFile.running = true;
		Qt.callLater(function () {
			root.shown = true;
			list.currentIndex = 0;
			field.focusInput();
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
		field.clear();
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
			const candidates = Helpers.windowAppCandidates(toplevel, Config.terminalClasses);
			const appId = candidates.word && AppIcons.iconOf(candidates.word) ? candidates.word : candidates.className;

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
		return root.actionEntries().concat(root.commandEntries()).concat(Helpers.appEntries(AppIcons.entries, Config.launcherIgnoreApps));
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
		list.move(step);
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
			Quickshell.execDetached(Helpers.launchCommand(entry, entry.appId, root.terminal));
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
		id: terminalFile

		command: ["sh", "-c", "cat " + Helpers.shellQuote(root.terminalConfig) + " 2>/dev/null"]

		stdout: StdioCollector {
			onStreamFinished: root.terminal = Helpers.terminalName(text)
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

	HyprBorder {
		id: card

		anchors.centerIn: parent

		width: Config.launcherWidth
		height: column.implicitHeight + card.inset * 2
		padding: Config.launcherPadding
		backgroundColor: Config.surfaceTranslucent
		visible: root.shown

		Column {
			id: column

			width: parent.width
			spacing: Config.launcherGap

			SearchField {
				id: field

				width: parent.width
				boxHeight: Config.launcherInputHeight
				padding: 0
				gap: Config.launcherTextGap
				glyphSlot: Config.launcherIconSlot
				glyphSize: Config.launcherIconSize
				size: Config.launcherFontSize
				glyph: root.prompt
				active: root.shown

				onEdited: {
					root.query = field.text;
					list.currentIndex = 0;
				}
				onAccepted: root.activate(root.results[list.currentIndex])
				onCanceled: root.close()
				onNavigate: function (step) { root.move(step); }
				onKeyPressed: function (event) {
					list.handleKey(event);
					if (event.accepted)
						return;

					if (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier) {
						root.pin(root.results[list.currentIndex]);
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

			Selector {
				id: list

				width: column.width
				height: root.listHeight
				visible: root.results.length > 0
				visibleRows: Config.launcherMaxRows
				rowHeight: Config.launcherRowHeight
				rowSpacing: Config.launcherGap
				model: root.results



				delegate: Item {
					id: row

					required property var modelData
					required property int index

					width: list.width
					height: Config.launcherRowHeight

					readonly property bool active: row.index === list.currentIndex
					readonly property bool pinned: root.pins.indexOf(row.modelData.id) >= 0

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
							source: row.modelData.appId !== undefined && row.modelData.appId !== "" ? AppIcons.iconOf(row.modelData.appId) : ""
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
						color: Config.foreground
						text: Config.launcherIconPin
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
