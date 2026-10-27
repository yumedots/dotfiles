import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.ui
import qs
import qs.services

PanelWindow {
	id: root

	signal powerRequested()

	property bool shown: false
	property string query: ""
	readonly property var pins: root.state.pins || []




	property string group: ""
	property string forced: ""
	property var pointer: null
	property var pending: null

	readonly property int windowColumns: windowsGrid.columns
	readonly property int winCurrent: Util.clamp(root.winIndex, 0, Math.max(0, root.results.length - 1))
	readonly property string winName: root.windows && root.results.length > 0 ? root.results[root.winCurrent].name : ""



	property bool windows: false
	property int winIndex: 0
	property string clipPreviewId: ""
	readonly property string clipPreviewText: root.state.clip ? String(root.state.clip.text || "") : ""
	readonly property string clipPreviewPath: root.state.clip && root.state.clip.path ? "file://" + root.state.clip.path : ""
	readonly property bool isClipboard: root.mode === "clipboard"

	readonly property var prefix: Apps.detectPrefix(root.query, Entries.modeMarks(Config.launcherModes))
	readonly property string search: root.windows || root.group !== "" || root.forced !== "" ? root.query : root.prefix.text
	readonly property string mode: root.windows ? "windows" : (root.group !== "" ? "group:" + root.group : (root.forced !== "" ? root.forced : root.prefix.mode))
	readonly property string home: Quickshell.env("HOME")
	readonly property string terminalConfig: Config.launcherTerminalConfig.replace("~", root.home)
	readonly property string stateDir: Quickshell.shellDir + "/cache/launcher"
	readonly property var appEntries: Entries.appEntries(AppIcons.entries, Config.launcherIgnoreApps, Config.launcherAppAliases)
	readonly property var state: Yudae.launcher
	readonly property var results: root.windows ? root.windowResults() : (root.state.results || [])

	function windowResults() {
		const typed = root.search.toLowerCase();

		return root.windowEntries().filter(function (entry) {
			return typed === "" || String(entry.name).toLowerCase().indexOf(typed) >= 0;
		});
	}
	readonly property int listHeight: Config.launcherMaxRows * Config.launcherRowHeight
	readonly property bool configured: root.screen !== null && root.width === root.screen.width && root.height > 1

	readonly property var modeInfo: Entries.modeInfo(root.mode, Config)
	readonly property string prompt: root.modeInfo && root.modeInfo.glyph ? root.modeInfo.glyph : Config.launcherPrompt

	anchors.top: true
	anchors.left: true
	anchors.bottom: true
	anchors.right: true

	implicitWidth: root.screen ? root.screen.width : 1
	implicitHeight: 1

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "launcher"
	WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
	WlrLayershell.focusable: true

	exclusiveZone: 0
	color: "transparent"

	margins.left: 0

	Region {
		id: emptyRegion

		width: 0
		height: 0
	}

	mask: root.shown ? null : emptyRegion

	property bool alwaysMapped: false

	visible: alwaysMapped || root.shown || card.opacity > 0

	Component.onCompleted: Yudae.launcherQuery(root.query, root.forced, root.group)

	function open(mode) {
		if (mode !== undefined)
			root.windows = false;

		root.query = "";
		root.group = "";
		root.forced = mode || "";
		root.pointer = null;
		list.currentIndex = 0;
		root.shown = true;
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

	function openClipboard() {
		root.open("clipboard");
	}

	function close() {
		root.shown = false;
		Yudae.launcherQuery("", "", "");
	}

	function settle() {
		root.query = "";
		root.group = "";
		root.forced = "";
		root.clipPreviewId = "";
		field.clear();
		field.typing = false;

		if (root.pending !== null) {
			root.remember(root.pending);
			root.pending = null;
		}
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
		return (Yudae.windows || []).map(function (info) {
			return {
				id: info.id,
				kind: "window",
				name: info.title || info.appId,
				appId: info.appId,
				keywords: [info.appId],
				address: info.address,
				workspace: info.workspace,
				focus: info.focus
			};
		});
	}

	function iconOfEntry(entry) {
		if (!entry)
			return "";

		if (entry.kind === "proc")
			return AppIcons.iconOfPid(entry.pid);

		return entry.appId ? AppIcons.iconOf(entry.appId) : "";
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
		if (!Input.switchRepeat())
			return;

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

		if (root.mode === "procs" && event.text === Config.procKillKey) {
			root.killProc(root.results[list.currentIndex]);
			event.accepted = true;
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
		if (root.group !== "") {
			root.leaveGroup();
				event.accepted = true;
				return;
			}

			root.close();
			event.accepted = true;
			return;
		}

		if (root.isClipboard && event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
			if (previewText.selectedText !== "") {
				Quickshell.execDetached(["sh", "-c", "touch " + Shell.shellQuote(Quickshell.env("XDG_RUNTIME_DIR") + "/qs-clip-self")]);
				root.copy(previewText.selectedText);
				event.accepted = true;
				return;
			}
		}

		if (root.isClipboard) {
			const page = Math.max(1, previewFlick.height - Config.launcherRowHeight);
			let delta = 0;

			if (event.key === Qt.Key_PageDown || (event.key === Qt.Key_Right && !field.typing))
				delta = page;
			else if (event.key === Qt.Key_PageUp || (event.key === Qt.Key_Left && !field.typing))
				delta = -page;

			if (delta !== 0) {
				root.scrollPreview(delta);
				event.accepted = true;
				return;
			}
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

		Yudae.launcherSave(root.query);
	}

	function writeFile(path, text) {
		Quickshell.execDetached(Shell.writeCommand(path, text));
	}

	function openWallpaper() {
		root.close();
		Quickshell.execDetached(["quickshell", "ipc", "call", "shell", "wallpaper"]);
	}

	function openPowerMenu() {
		root.close();
		root.powerRequested();
	}

	function remember(entry) {
		if (!entry || entry.kind === "calc" || entry.kind === "window" || entry.kind === "proc" || entry.kind === "clip")
			return;

		Yudae.launcherRemember(entry.id);
	}

	function pin(entry) {
		if (!Entries.rememberable(entry))
			return;

		Yudae.launcherPin(entry.id);
	}

	function copy(text) {
		Quickshell.execDetached(["sh", "-c", "printf '%s' " + Shell.shellQuote(text) + " | wl-copy"]);
	}

	function copyClip(id) {
		Yudae.launcherCopyClip(id);
	}

	function decodeClip(clipId) {
		const id = clipId || "";

		if (root.clipPreviewId === id)
			return;

		root.clipPreviewId = id;
		Yudae.launcherClip(id);
	}

	function decodeCurrentClip() {
		if (!root.isClipboard)
			return;

		const entry = root.results[list.currentIndex >= 0 ? list.currentIndex : 0];

		root.decodeClip(entry && entry.clipId ? entry.clipId : "");
	}

	function scrollPreview(delta) {
		if (typeof previewFlick !== "undefined" && previewFlick) {
			previewFlick.contentY = Util.clamp(
				previewFlick.contentY + delta,
				0,
				Math.max(0, previewFlick.contentHeight - previewFlick.height)
			);
		}
	}

	function focusWindow(address) {
		Yudae.windowFocus(address);
	}

	function killProc(entry) {
		if (!entry || entry.kind !== "proc")
			return;

		Yudae.launcherKill(entry.pid);
	}

	function activate(entry) {
		if (!entry)
			return;

		if (entry.kind === "mode") {
			if (entry.mode === "wallpaper") {
				root.openWallpaper();
				return;
			}

			root.group = "";
			root.forced = entry.mode;
			root.query = "";
			field.clear();
			list.currentIndex = 0;
			return;
		}

		if (entry.kind === "group") {
			if (entry.group === "power") {
				root.openPowerMenu();
				return;
			}

			root.group = entry.group;
			root.query = "";
			field.clear();
			list.currentIndex = 0;
			return;
		}

		if (!root.shown)
			return;

		if (entry.kind === "app")
			Yudae.windowLaunch(entry.appId);
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

		root.pending = entry;
		root.close();
	}

	onSearchChanged: Yudae.launcherQuery(root.query, root.forced, root.group)

	onResultsChanged: root.decodeCurrentClip()

	onModeChanged: {
		list.currentIndex = 0;
		Yudae.launcherQuery(root.query, root.forced, root.group);

		if (root.mode === "wallpaper")
			root.openWallpaper();
		else if (root.mode === "clipboard") {
			Yudae.launcherClips();
		}
	}

















	MouseArea {
		id: backdrop

		anchors.fill: parent
		enabled: root.shown

		onClicked: function (mouse) {
			if (!card.contains(card.mapFromItem(backdrop, mouse.x, mouse.y)))
				root.close();
		}
	}

	HyprBorder {
		id: card

		anchors.centerIn: parent

		width: root.windows ? windowsGrid.implicitWidth + card.inset * 2
		      : root.isClipboard ? Config.launcherWidth * 2 + Config.launcherGap + card.inset * 2
		      : Config.launcherWidth
		height: root.windows ? windowsGrid.implicitHeight + card.inset * 2 : column.implicitHeight + card.inset * 2
		padding: Config.launcherPadding
		backgroundColor: Config.surfaceTranslucent
		opacity: root.shown ? 1 : 0
		visible: root.configured && (root.shown || opacity > 0)
		focus: true

		onOpacityChanged: {
			if (opacity !== 0)
				return;

			root.settle();
		}

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

			// ── results pane: clipboard preview + list ────────────────────
			Item {
				width: parent.width
				height: root.listHeight

				// right pane: clipboard text preview, nothing else
				Item {
					id: previewPane

					anchors.right: parent.right
					anchors.top: parent.top
					anchors.bottom: parent.bottom
					visible: root.isClipboard
					width: root.isClipboard ? (parent.width - Config.launcherGap) / 2 : 0
					clip: true

					// the decoded text; keyboard paging jumps instantly,
					// no smooth scrolling and no scrollbar
					Flickable {
						id: previewFlick

						anchors.fill: parent
						anchors.margins: Config.launcherTextGap
						visible: root.clipPreviewPath === ""
						clip: true
						contentWidth: width
						contentHeight: previewText.contentHeight
						boundsBehavior: Flickable.StopAtBounds
						interactive: false

						TextEdit {
							id: previewText

							width: previewFlick.width
							readOnly: true
							selectByMouse: true
							selectByKeyboard: false
							activeFocusOnPress: false
							persistentSelection: true
							cursorVisible: false
							wrapMode: TextEdit.Wrap
							font.family: Config.fontFamily
							font.pixelSize: Config.fontSize
							color: root.clipPreviewText === "" ? Config.muted : Config.foreground
							text: root.clipPreviewText
							textFormat: TextEdit.PlainText
							selectionColor: Config.launcherHighlight
							selectedTextColor: Config.launcherHighlightText
						}

						MouseArea {
							anchors.fill: parent
							acceptedButtons: Qt.NoButton

							onWheel: function (wheel) {
								root.scrollPreview(wheel.angleDelta.y > 0 ? -Config.launcherRowHeight : Config.launcherRowHeight);
								wheel.accepted = true;
							}
						}
					}

					// image clips mirror the wallpaper preview mechanics
					Image {
						id: clipShot

						anchors.fill: parent
						anchors.margins: Config.launcherTextGap
						visible: root.clipPreviewPath !== ""
						fillMode: Image.PreserveAspectFit
						cache: true
						asynchronous: true
						retainWhileLoading: true
						source: root.clipPreviewPath === "" ? "" : root.clipPreviewPath
					}
				}
				// left pane: the results list
				Item {
					id: listPane

					anchors.left: parent.left
					anchors.right: root.isClipboard ? previewPane.left : parent.right
					anchors.rightMargin: root.isClipboard ? Config.launcherGap : 0
					anchors.top: parent.top
					anchors.bottom: parent.bottom

					Selector {
						id: list

						anchors.fill: parent
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

							readonly property string clipIcon: row.modelData.kind === "clip" && row.modelData.appId ? AppIcons.iconOf(row.modelData.appId) : ""
							readonly property string icon: rowIcon.clipIcon !== "" ? rowIcon.clipIcon : root.iconOfEntry(row.modelData)

							Text {
								visible: row.modelData.kind !== "app" && (rowIcon.icon === "" || rowIconImage.status === Image.Error)
								anchors.centerIn: parent
								font.family: Config.fontFamily
								font.pixelSize: 18
								color: row.active ? Config.launcherHighlightText : Config.foreground
								text: root.rowGlyph(row.modelData)
								z: 1
							}

							Rectangle {
								anchors.centerIn: parent
								width: Config.launcherIconSize
								height: Config.launcherIconSize
								radius: 3
								color: Config.surface
								visible: row.modelData.kind === "app" && (rowIcon.icon === "" || rowIconImage.status === Image.Error)
							}

							AppIcon {
								id: rowIconImage

								anchors.centerIn: parent
								implicitSize: Config.launcherIconSize
								visible: rowIcon.icon !== ""
								source: rowIcon.icon
								z: 2
							}
							}

							Text {
								anchors.left: rowIcon.right
								anchors.leftMargin: Config.launcherTextGap
								anchors.right: rowUsage.left
								anchors.rightMargin: Config.launcherTextGap
								anchors.verticalCenter: parent.verticalCenter
								elide: Text.ElideRight
								font.family: Config.fontFamily
								font.pixelSize: Config.launcherFontSize
								color: row.active ? Config.launcherHighlightText : Config.foreground
								text: row.modelData.name
							}

							Text {
								id: rowUsage

								anchors.right: parent.right
								anchors.rightMargin: Config.launcherPadding
								anchors.verticalCenter: parent.verticalCenter
								width: visible ? implicitWidth : 0
								visible: row.modelData.kind === "proc"
								font.family: Config.fontFamily
								font.pixelSize: Config.launcherFontSize
								color: row.active ? Config.launcherHighlightText : Config.muted
								text: row.modelData.kind === "proc" ? row.modelData.value.toFixed(1) + "%" : ""
							}

							Text {
								id: rowPin

								anchors.right: rowUsage.left
								anchors.rightMargin: Config.launcherTextGap
								anchors.verticalCenter: parent.verticalCenter
								visible: row.pinned
								font.family: Config.fontFamily
								font.pixelSize: Config.launcherIconSize
								color: Config.foreground
								text: Config.launcherIconPin
							}
							HoverHandler {
								onPointChanged: {
									if (!hovered)
										return;

									const next = Util.pointerMoved(root.pointer, point.scenePosition, Config.launcherRowHeight);

									root.pointer = next;

									if (next.moved)
										list.currentIndex = row.index;
								}
							}

							MouseArea {
								anchors.fill: parent

								onClicked: {
									if (row.modelData.kind === "proc" && row.active) {
										root.killProc(row.modelData);
										return;
									}

									list.currentIndex = row.index;
									root.activate(row.modelData);
								}
							}
						}
					}

					// decode on selection change without shadowing Selector's handlers
					Connections {
						target: list

						function onCurrentIndexChanged() {
							root.decodeCurrentClip();
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

		WindowSwitcher {
			id: windowsGrid

			visible: root.windows
			results: root.windows ? root.results : []
			index: root.winCurrent
			title: root.winName
			emptyMessage: root.emptyText()
			available: root.screen ? root.screen.width : root.width
		}
	}
}
