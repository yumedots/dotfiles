import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.ui
import qs
import qs.services

PanelWindow {
	id: root

	signal powerRequested()

	property bool shown: false
	property string query: ""
	property string group: ""
	property string forced: ""
	property var pointer: null
	property var pending: null
	property string clipAsked: ""
	property bool grabbed: false
	property string anchorId: ""
	property string anchorKey: ""
	property bool following: false
	property bool freshAnchor: false

	property bool windows: false
	property int winIndex: 0

	readonly property var state: Yudae.launcher
	readonly property string mode: root.windows ? "windows" : (root.state.mode || "apps")
	readonly property string prompt: root.windows ? "" : (root.state.prompt || "")
	readonly property bool isClipboard: root.mode === "clipboard"
	readonly property string empty: root.windows ? Yudae.windowsEmpty : (root.state.empty || "")
	readonly property var results: root.windows ? (Yudae.windows || []) : (root.state.results || [])
	readonly property string clipPreviewText: root.state.clip ? String(root.state.clip.text || "") : ""
	readonly property string clipPreviewPath: root.state.clip && root.state.clip.path ? "file://" + root.state.clip.path : ""

	readonly property int selectedIndex: root.results.length === 0 ? -1 : Calc.clamp(list.currentIndex < 0 ? 0 : list.currentIndex, 0, root.results.length - 1)
	readonly property var selectedRow: root.selectedIndex >= 0 ? root.results[root.selectedIndex] : null
	readonly property string wantedClip: root.shown && root.isClipboard && root.selectedRow && root.selectedRow.clipId ? root.selectedRow.clipId : ""

	readonly property int windowColumns: windowsGrid.columns
	readonly property int winCurrent: Calc.clamp(root.winIndex, 0, Math.max(0, root.results.length - 1))
	readonly property string winName: root.windows && root.results.length > 0 ? root.results[root.winCurrent].name : ""

	readonly property int listHeight: Config.launcherMaxRows * Config.launcherRowHeight
	readonly property bool configured: root.screen !== null && root.width === root.screen.width && root.height > 1

	anchors.top: true
	anchors.left: true
	anchors.bottom: true
	anchors.right: true

	implicitWidth: root.screen ? root.screen.width : 1
	implicitHeight: root.screen ? root.screen.height : 1

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "launcher"
	WlrLayershell.keyboardFocus: root.shown && root.grabbed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
	WlrLayershell.focusable: true

	exclusiveZone: -1
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

	Component.onCompleted: {
		if (root.alwaysMapped)
			root.push();
	}

	Timer {
		id: grabTimer

		interval: 16

		onTriggered: {
			if (!root.shown)
				return;

			root.grabbed = true;

			if (field.typing)
				field.focusInput();
			else
				card.forceActiveFocus();
		}
	}

	function grab() {
		if (!root.shown || root.grabbed)
			return;

		root.grabbed = false;
		grabTimer.restart();
	}

	function anchor() {
		if (root.following)
			return;

		root.anchorId = root.selectedRow ? root.selectedRow.id : "";
		root.anchorKey = root.mode + "\u0000" + (root.state.query || "");
	}

	function followResults() {
		const key = root.mode + "\u0000" + (root.state.query || "");

		if (root.freshAnchor || root.mode !== "procs" || root.anchorKey !== key) {
			root.freshAnchor = false;
			root.anchor();
			return;
		}

		root.restoreAnchor();
	}

	function restoreAnchor() {
		if (root.anchorId === "" || root.results.length === 0)
			return;

		for (let i = 0; i < root.results.length; i++) {
			if (root.results[i].id !== root.anchorId)
				continue;

			if (list.currentIndex === i)
				return;

			root.following = true;
			list.currentIndex = i;
			root.following = false;
			return;
		}
	}

	function requestClip() {
		if (root.clipAsked === root.wantedClip)
			return;

		root.clipAsked = root.wantedClip;
		Yudae.cmd("launcher", { clip: root.clipAsked });
	}

	function push() {
		if (root.windows) {
			Yudae.cmd("windows", { query: root.query });
			return;
		}

		Yudae.cmd("launcher", { query: root.query, forced: root.forced, group: root.group });
	}

	function open(mode) {
		if (mode !== undefined)
			root.windows = false;

		root.query = "";
		root.group = "";
		root.forced = mode || "";
		root.pointer = null;
		root.anchorId = "";
		root.anchorKey = "";
		root.freshAnchor = true;
		list.currentIndex = 0;
		root.shown = true;
		root.winIndex = root.windows ? 1 : 0;
		root.grabbed = false;
		root.push();
		root.grab();
		root.anchor();
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
		root.anchorId = "";
		root.anchorKey = "";
		Yudae.cmd("launcher", { query: "", forced: "", group: "" });
		Yudae.cmd("windows", { query: "" });
	}

	function settle() {
		root.query = "";
		root.group = "";
		root.forced = "";
		field.clear();
		field.typing = false;

		if (root.pending !== null) {
			Yudae.cmd("launcher", { remember: root.pending.id });
			root.pending = null;
		}

		root.push();
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

	function stepWindows(step) {
		if (!Input.switchRepeat())
			return;

		root.winIndex = root.results.length > 0 ? ((root.winIndex + step) % root.results.length + root.results.length) % root.results.length : 0;
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
			root.killProc(root.selectedRow);
			event.accepted = true;
			return;
		}

		if (!field.typing && event.text === Config.procHintKey) {
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
				Yudae.cmd("launcher", { copyText: previewText.selectedText });
				root.grab();
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
			root.activate(root.selectedRow);
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

		root.pin(root.selectedRow);
		event.accepted = true;
	}

	function leaveGroup() {
		root.group = "";
		root.forced = "";
		root.query = "";
		field.clear();
		list.currentIndex = 0;
		root.push();
	}

	function saveQuery() {
		if (root.query === "" || root.windows)
			return;

		Yudae.cmd("launcher", { save: root.query });
	}

	function openWallpaper() {
		root.close();

		const pid = Quickshell.env("QS_MAIN_PID");

		if (pid)
			Quickshell.execDetached(["quickshell", "ipc", "--pid", pid, "call", "shell", "wallpaper"]);
		else
			Quickshell.execDetached(["quickshell", "ipc", "call", "shell", "wallpaper"]);
	}

	function openPowerMenu() {
		root.close();
		root.powerRequested();
	}

	function pin(entry) {
		if (!entry)
			return;

		Yudae.cmd("launcher", { pin: entry.id });
	}

	function copyClip(id) {
		Yudae.cmd("launcher", { copyClip: id });
		root.grab();
	}

	function scrollPreview(delta) {
		if (typeof previewFlick !== "undefined" && previewFlick) {
			previewFlick.contentY = Calc.clamp(
				previewFlick.contentY + delta,
				0,
				Math.max(0, previewFlick.contentHeight - previewFlick.height)
			);
		}
	}

	function killProc(entry) {
		if (!entry || entry.kind !== "proc")
			return;

		Yudae.cmd("launcher", { kill: entry.pid });
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
			root.push();
			return;
		}

		if (entry.kind === "group") {
			if (entry.group === "power") {
				root.openPowerMenu();
				return;
			}

			root.forced = "";
			root.group = entry.group;
			root.query = "";
			field.clear();
			list.currentIndex = 0;
			root.push();
			return;
		}

		if (!root.shown)
			return;

		Yudae.cmd("launcher", { activate: entry.id });
		root.pending = entry;
		root.close();
	}

	onQueryChanged: root.push()

	onStateChanged: {
		const intent = root.state.intent;

		if (root.windows || !root.shown || !intent)
			return;

		if (intent.query === root.query && intent.forced === root.forced && intent.group === root.group)
			return;

		root.push();
	}

	onWantedClipChanged: root.requestClip()

	onResultsChanged: root.followResults()

	onModeChanged: {
		list.currentIndex = 0;

		if (!root.shown)
			return;

		if (root.mode === "wallpaper")
			root.openWallpaper();
		else if (root.mode === "clipboard")
			Yudae.cmd("launcher", { clips: true });

		root.grab();
	}

	Connections {
		target: Yudae

		function onConnectedChanged() {
			if (!Yudae.connected || !root.shown)
				return;

			root.push();
			root.clipAsked = "";
			root.requestClip();
			root.grab();
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

		Behavior on opacity {
			NumberAnimation { duration: Config.popupFadeMs; easing.type: Easing.OutCubic }
		}

		layer.enabled: opacity > 0 && opacity < 1
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
				hintKey: Config.procHintKey
				hintText: Config.procSearchHint
				padding: 0
				gap: Config.launcherTextGap
				glyphSlot: Config.launcherIconSlot
				glyphSize: Config.launcherIconSize
				size: Config.launcherFontSize
				glyph: root.prompt

				onEdited: {
					root.query = field.text;
					list.currentIndex = 0;
				}
				onAccepted: root.activate(root.selectedRow)
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
							readonly property bool pinned: row.modelData.pinned === true

							Item {
								id: rowIcon

								anchors.left: parent.left
								anchors.verticalCenter: parent.verticalCenter
								width: Config.launcherIconSlot
								height: Config.launcherIconSlot

							readonly property string icon: row.modelData.kind === "proc" ? AppIcons.iconOfPid(row.modelData.pid) : (row.modelData.appId ? AppIcons.iconOf(row.modelData.appId) : "")

							Text {
								visible: row.modelData.kind !== "app" && (rowIcon.icon === "" || rowIconImage.status === Image.Error)
								anchors.centerIn: parent
								font.family: Config.fontFamily
								font.pixelSize: 18
								color: row.active ? Config.launcherHighlightText : Config.foreground
								text: row.modelData.glyph
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
								text: row.modelData.detail
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

									const at = point.scenePosition;
									const prev = root.pointer;

									if (!prev) {
										root.pointer = { x: at.x, y: at.y, engaged: false };
										return;
									}

									if (prev.engaged || (at.x - prev.x) ** 2 + (at.y - prev.y) ** 2 >= Config.launcherRowHeight ** 2) {
										root.pointer = { x: at.x, y: at.y, engaged: true };

										if (at.x !== prev.x || at.y !== prev.y)
											list.currentIndex = row.index;
									}
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

					Connections {
						target: list

						function onCurrentIndexChanged() {
							root.anchor();
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
							text: root.empty
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
			emptyMessage: root.empty
			available: root.screen ? root.screen.width : root.width
		}
	}
}
