import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
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
	property var saved: []
	property string group: ""
	property string forced: ""

	readonly property int windowColumns: windowsGrid.columns
	readonly property int winCurrent: Util.clamp(root.winIndex, 0, Math.max(0, root.results.length - 1))
	readonly property string winName: root.windows && root.results.length > 0 ? root.results[root.winCurrent].name : ""
	property var clips: []
	property bool windows: false
	property int winIndex: 0

	readonly property var prefix: Apps.detectPrefix(root.query, Entries.modeMarks(Config.launcherModes))
	readonly property string search: root.windows || root.group !== "" || root.forced !== "" ? root.query : root.prefix.text
	readonly property string mode: root.windows ? "windows" : (root.group !== "" ? "group:" + root.group : (root.forced !== "" ? root.forced : root.prefix.mode))
	readonly property string home: Quickshell.env("HOME")
	readonly property string terminalConfig: Config.launcherTerminalConfig.replace("~", root.home)
	readonly property string stateDir: Quickshell.shellDir + "/cache/launcher"
	readonly property var appEntries: Entries.appEntries(AppIcons.entries, Config.launcherIgnoreApps, Config.launcherAppAliases)
	readonly property var results: Apps.results(root.mode, root.search, {
		clips: root.clips,
		windows: root.windowEntries(),
		entries: Entries.all(Config, root.appEntries, root.saved),
		groups: ({ apps: root.appEntries }),
		pins: root.pins,
		usage: root.usage,
		calc: Parse.calcEntry(root.search)
	})
	readonly property int listHeight: Config.launcherMaxRows * Config.launcherRowHeight
	readonly property bool configured: root.screen !== null && root.width === root.screen.width

	readonly property var modeInfo: Entries.modeInfo(root.mode, Config)
	readonly property string prompt: root.modeInfo && root.modeInfo.glyph ? root.modeInfo.glyph : Config.launcherPrompt

	anchors.top: true
	anchors.left: true
	anchors.bottom: true
	anchors.right: root.mapped

	implicitWidth: root.screen ? root.screen.width : 1
	implicitHeight: 1

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "launcher"
	WlrLayershell.keyboardFocus: root.mapped ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
	WlrLayershell.focusable: true

	exclusiveZone: 0
	color: "transparent"

	margins.left: root.mapped ? 0 : (root.screen ? root.screen.width : 0)

	// ponytail: the surface keeps the screen's size and slides off it while closed
	// instead of being resized on open. A resize is what let hyprland hold a stale
	// frame over the screen, and a click on that frame landed on the wrong row.
	// Ceiling: a full screen surface stays mapped off screen.

	function open() {
		root.query = "";
		root.clips = [];
		root.group = "";
		root.forced = "";
		Hyprland.refreshToplevels();
		pinsFile.running = true;
		usageFile.running = true;
		terminalFile.running = true;
		savedFile.running = true;
		root.shown = true;
		root.mapped = true;
		root.winIndex = root.windows ? 1 : 0;
		Qt.callLater(function () {
			list.currentIndex = 0;
			card.forceActiveFocus();
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
		root.group = "";
		root.forced = "";
		field.clear();
		field.typing = false;
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

	function windowEntries() {
		const values = Hyprland.toplevels.values ? Hyprland.toplevels.values : [];

		return values.map(function (toplevel) {
			const info = toplevel.lastIpcObject ? toplevel.lastIpcObject : {};
			const candidates = Apps.windowAppCandidates(toplevel, Config.terminalClasses);
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

	function rowGlyph(entry) {
		return Entries.glyphOf(entry, Config);
	}

	function emptyText() {
		if (root.mode === "clipboard")
			return "Nothing copied yet";
		if (root.mode === "windows")
			return "No windows open";
		if (root.mode === "calc")
			return "Type an expression";
		if (root.group !== "")
			return "Nothing here";

		return "Nothing matches";
	}

	function stepWindows(step) {
		root.winIndex = Util.wrap(root.winIndex, step, root.results.length);
	}

	function handleRelease(event) {
		if (!root.windows)
			return;

		if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta) {
			root.activate(root.results[root.winCurrent]);
			event.accepted = true;
		}
	}

	function handleKeys(event) {
		if (root.windows) {
			Input.switcher(event, root);
			return;
		}

		if (Input.hint(event)) {
			field.startTyping();
			event.accepted = true;
			return;
		}

		if (Input.save(event)) {
			root.saveQuery();
			event.accepted = true;
			return;
		}

		if (Input.cancel(event)) {
		if (root.group !== "" || root.forced !== "") {
			root.leaveGroup();
				event.accepted = true;
				return;
			}

			root.close();
			event.accepted = true;
			return;
		}

		if (!field.typing && Input.accept(event)) {
			root.activate(root.results[list.currentIndex]);
			event.accepted = true;
			return;
		}

		if (root.navigate(Input.direction(event))) {
			event.accepted = true;
			return;
		}

		root.pinKey(event);
	}

	function handleTypingKeys(event) {
		if (Input.cancel(event))
			return;

		if (Input.save(event)) {
			root.saveQuery();
			event.accepted = true;
			return;
		}

		if (root.navigate(Input.arrows[event.key] || "")) {
			event.accepted = true;
			return;
		}

		root.pinKey(event);
	}

	function navigate(dir) {
		if (dir === "down" || dir === "up") {
			list.move(dir === "down" ? 1 : -1);
			return true;
		}

		return false;
	}

	function pinKey(event) {
		if (!Input.pin(event))
			return;

		root.pin(root.results[list.currentIndex]);
		event.accepted = true;
	}

	function leaveGroup() {
		root.group = "";
		root.forced = "";
		root.query = "";
		field.clear();
		list.currentIndex = 0;
	}

	function saveQuery() {
		if (root.query === "" || root.windows)
			return;

		root.saved = Entries.toggleCustom(root.saved, root.query);
		root.writeFile(root.stateDir + "/entries.txt", Entries.formatCustom(root.saved));
	}

	function writeFile(path, text) {
		Quickshell.execDetached(Shell.writeCommand(path, text));
	}

	function remember(entry) {
		if (!Entries.rememberable(entry))
			return;

		root.usage = Apps.bumpUsage(root.usage, entry.id, Date.now());
		root.writeFile(root.stateDir + "/usage.txt", Apps.formatUsage(root.usage, Config.launcherUsageMax));
	}

	function pin(entry) {
		if (!Entries.rememberable(entry))
			return;

		root.pins = Apps.togglePin(root.pins, entry.id);
		root.writeFile(root.stateDir + "/pins.txt", root.pins.join("\n"));
	}

	function copy(text) {
		Quickshell.execDetached(["sh", "-c", "printf '%s' " + Shell.shellQuote(text) + " | wl-copy"]);
	}

	function copyClip(id) {
		const command = "out=$(mktemp) && cliphist decode " + Shell.shellQuote(id) + " > \"$out\" && [ -s \"$out\" ] && wl-copy < \"$out\"; rm -f \"$out\"";

		Quickshell.execDetached(["sh", "-c", command]);
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

		if (entry.kind === "mode") {
			root.group = "";
			root.forced = entry.mode;
			root.query = "";
			field.clear();
			list.currentIndex = 0;
			return;
		}

		if (entry.kind === "group") {
			root.group = entry.group;
			root.query = "";
			field.clear();
			list.currentIndex = 0;
			return;
		}

		if (!root.shown)
			return;

		if (entry.kind === "app")
			Quickshell.execDetached(Apps.launchCommand(entry, entry.appId, root.terminal));
		else if (entry.kind === "window")
			root.focusWindow(entry.address);
		else if (entry.kind === "command" || entry.kind === "action" || entry.kind === "saved")
			Quickshell.execDetached(["sh", "-c", entry.command]);
		else if (entry.kind === "calc")
			root.copy(entry.value);
		else if (entry.kind === "clip")
			root.copyClip(entry.clipId);
		else if (entry.kind === "file")
			Quickshell.execDetached(["xdg-open", entry.path]);

		root.remember(entry);
		root.close();
	}

	onModeChanged: {
		if (root.mode === "clipboard")
			clipsList.running = true;
	}

	Request {
		id: pinsFile

		command: Shell.readCommand(root.stateDir + "/pins.txt")

		onDone: function (text) {
			root.pins = Apps.pinnedFromText(text);
		}
	}

	Request {
		id: usageFile

		command: Shell.readCommand(root.stateDir + "/usage.txt")

		onDone: function (text) {
			root.usage = Apps.parseUsage(text);
		}
	}

	Request {
		id: savedFile

		command: Shell.readCommand(root.stateDir + "/entries.txt")

		onDone: function (text) {
			root.saved = Entries.customEntries(text);
		}
	}

	Request {
		id: terminalFile

		command: Shell.readCommand(root.terminalConfig)

		onDone: function (text) {
			root.terminal = Apps.terminalName(text);
		}
	}

	Request {
		id: clipsList

		command: ["sh", "-c", "cliphist list 2>/dev/null | head -n " + Config.launcherMaxResults]

		onDone: function (text) {
			root.clips = Entries.clipEntries(Parse.parseClipboardList(text));
		}
	}

	MouseArea {
		id: backdrop

		anchors.fill: parent

		onClicked: function (mouse) {
			if (!card.contains(card.mapFromItem(backdrop, mouse.x, mouse.y)))
				root.close();
		}
	}

	HyprBorder {
		id: card

		anchors.centerIn: parent

		width: root.windows ? windowsGrid.width + card.inset * 2 : Config.launcherWidth
		height: root.windows ? windowsGrid.height + windowName.height + Config.windowsLabelGap + card.inset * 2 : column.implicitHeight + card.inset * 2
		padding: Config.launcherPadding
		backgroundColor: Config.surfaceTranslucent
		visible: root.shown && root.configured
		focus: true

		Keys.onPressed: function (event) { root.handleKeys(event); }
		Keys.onReleased: function (event) { root.handleRelease(event); }

		Column {
			id: column

			visible: !root.windows
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
				hintKey: Config.procSearchHint

				onEdited: {
					root.query = field.text;
					list.currentIndex = 0;
				}
				onAccepted: root.activate(root.results[list.currentIndex])
				onKeyPressed: function (event) { root.handleTypingKeys(event); }
				onTypingChanged: {
					if (!field.typing)
						card.forceActiveFocus();
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
					readonly property bool pinned: root.pins.indexOf(row.modelData.id) >= 0 || row.modelData.kind === "saved"

					Item {
						id: rowIcon

						anchors.left: parent.left
						anchors.verticalCenter: parent.verticalCenter
						width: Config.launcherIconSlot
						height: Config.launcherIconSlot

						AppIcon {
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

						HoverHandler {
							onHoveredChanged: {
								if (hovered)
									list.currentIndex = row.index;
							}
						}

						MouseArea {
							anchors.fill: parent

							onClicked: {
								list.currentIndex = row.index;
								root.activate(row.modelData);
							}
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

		Item {
			id: windowsGrid

			readonly property real cell: Config.windowsGridCell
			readonly property int count: root.results.length
			readonly property real freeWidth: (root.screen ? root.screen.width : root.width) - Config.windowsRowMargin
			readonly property int columns: Math.max(1, Math.min(count, Math.floor(freeWidth / cell)))
			readonly property int index: root.winCurrent
			readonly property real emptyWidth: count === 0 ? emptyText.implicitWidth : 0

			visible: root.windows
			width: Math.max(columns * cell, emptyWidth)
			height: Math.ceil(Math.max(count, 1) / columns) * cell
			clip: true

			Highlight {
				fillParent: false
				active: windowsGrid.count > 0
				x: (windowsGrid.index % windowsGrid.columns) * windowsGrid.cell + (windowsGrid.cell - Config.windowsHighlightSize) / 2
				y: Math.floor(windowsGrid.index / windowsGrid.columns) * windowsGrid.cell + (windowsGrid.cell - Config.windowsHighlightSize) / 2
				width: Config.windowsHighlightSize
				height: Config.windowsHighlightSize
			}

			Repeater {
				model: root.results

				delegate: Item {
					id: iconCell

					required property var modelData
					required property int index

					readonly property string icon: modelData.appId !== undefined && modelData.appId !== "" ? AppIcons.iconOf(modelData.appId) : ""
					x: (index % windowsGrid.columns) * windowsGrid.cell
					y: Math.floor(index / windowsGrid.columns) * windowsGrid.cell
					width: windowsGrid.cell
					height: windowsGrid.cell

					AppIcon {
						anchors.centerIn: parent
						implicitSize: Config.windowsIconSize
						visible: iconCell.icon !== ""
						source: iconCell.icon
					}

					Text {
						anchors.centerIn: parent
						visible: iconCell.icon === ""
						font.family: Config.fontFamily
						font.pixelSize: Config.windowsIconSize
						color: Config.foreground
						text: root.rowGlyph(iconCell.modelData)
					}
				}
			}

			Text {
				id: emptyText

				anchors.centerIn: parent
				visible: windowsGrid.count === 0
				font.family: Config.fontFamily
				font.pixelSize: Config.launcherFontSize
				color: Config.muted
				text: root.emptyText()
			}
		}

		Text {
			id: windowName

			visible: root.windows
			width: Math.min(implicitWidth, windowsGrid.width)
			x: Util.clamp(windowsGrid.index * windowsGrid.cell + (windowsGrid.cell - width) / 2, 0, windowsGrid.width - width)
			anchors.top: windowsGrid.bottom
			anchors.topMargin: Config.windowsLabelGap
			horizontalAlignment: Text.AlignHCenter
			elide: Text.ElideRight
			font.family: Config.fontFamily
			font.pixelSize: Config.windowsTitleSize
			color: Config.foreground
			text: root.winName
		}
	}
}
