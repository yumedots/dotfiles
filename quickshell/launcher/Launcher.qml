import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.ui
import qs
import qs.services

PanelWindow {
	id: root

	signal powerRequested()

	property bool shown: false
	property string query: ""
	property var pins: []
	property string terminal: ""
	property var usage: ({})
	property var procs: []
	property var procRows: []
	property var saved: []
	property string group: ""
	property string forced: ""
	property var pointer: null
	property var pending: null

	readonly property int windowColumns: windowsGrid.columns
	readonly property int winCurrent: Util.clamp(root.winIndex, 0, Math.max(0, root.results.length - 1))
	readonly property string winName: root.windows && root.results.length > 0 ? root.results[root.winCurrent].name : ""
	property var clips: []
	property var clipList: []
	property string clipSources: ""
	property bool windows: false
	property int winIndex: 0
	property string pendingFocus: ""
	property string clipPreviewText: ""
	property string clipPreviewId: ""
	property bool clipPreviewLoading: false
	property string clipPreviewPath: ""
	readonly property bool isClipboard: root.mode === "clipboard"

	readonly property var prefix: Apps.detectPrefix(root.query, Entries.modeMarks(Config.launcherModes))
	readonly property string search: root.windows || root.group !== "" || root.forced !== "" ? root.query : root.prefix.text
	readonly property string mode: root.windows ? "windows" : (root.group !== "" ? "group:" + root.group : (root.forced !== "" ? root.forced : root.prefix.mode))
	readonly property string home: Quickshell.env("HOME")
	readonly property string terminalConfig: Config.launcherTerminalConfig.replace("~", root.home)
	readonly property string stateDir: Quickshell.shellDir + "/cache/launcher"
	property var versions: ({})
	readonly property var appEntries: Entries.appEntries(AppIcons.entries, Config.launcherIgnoreApps, Config.launcherAppAliases)
	readonly property var data: Yudae.launcher
	readonly property var results: root.windows ? root.windowResults() : (root.data.results || [])

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

	onVisibleChanged: {
		if (root.visible || root.pendingFocus === "")
			return;

		const address = root.pendingFocus;

		root.pendingFocus = "";
		root.focusWindow(address);
	}

	Timer {
		id: pendingFocusTimer

		interval: 30
		repeat: true

		onTriggered: {
			if (root.pendingFocus === "") {
				pendingFocusTimer.stop();
				return;
			}

			const address = root.pendingFocus;
			root.pendingFocus = "";
			root.focusWindow(address);
		}
	}

	Component.onCompleted: {
		clipsList.running = true;
		pinsFile.running = true;
		usageFile.running = true;
		terminalFile.running = true;
		savedFile.running = true;
		procList.running = true;
	}

	function open(mode) {
		if (mode !== undefined)
			root.windows = false;

		root.query = "";
		root.pendingFocus = "";
		root.group = "";
		root.forced = mode || "";
		root.pointer = null;
		list.currentIndex = 0;
		Hyprland.refreshToplevels();
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

		if (root.pendingFocus !== "")
			pendingFocusTimer.restart();
	}

	function settle() {
		root.query = "";
		root.group = "";
		root.forced = "";
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
		const all = Apps.realWindows(Hyprland.toplevels.values ? Hyprland.toplevels.values : []);
		const values = all.filter(function (toplevel) {
			const info = toplevel.lastIpcObject;
			if (!info || !info.workspace) return false;

			const match = String(info.workspace.name || "").match(/^v?(\d+)(?:\.(\d+))?$/);
			if (!match) return false;

			const slot = parseInt(match[1], 10);
			const version = match[2] ? parseInt(match[2], 10) : 1;

			return version === (root.versions[slot] || 1);
		});

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
				workspace: info.workspace,
				focus: info.focusHistoryID === undefined ? 999 : info.focusHistoryID
			};
		}).sort(function (a, b) {
			return a.focus - b.focus;
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
		const command = "out=$(mktemp) && cliphist decode " + Shell.shellQuote(id) + " > \"$out\" && [ -s \"$out\" ] && wl-copy < \"$out\"; rm -f \"$out\"";

		Quickshell.execDetached(["sh", "-c", command]);
	}

	function decodeClip(clipId) {
		if (!clipId) {
			root.clipPreviewText = "";
			root.clipPreviewId = "";
			root.clipPreviewLoading = false;
			root.clipPreviewPath = "";
			return;
		}
		if (root.clipPreviewId === clipId && (root.clipPreviewText !== "" || root.clipPreviewPath !== ""))
			return;

		const entry = root.clipEntry(clipId);

		root.clipPreviewId = clipId;
		root.clipPreviewLoading = true;
		root.clipPreviewPath = "";

		if (entry && entry.image) {
			clipImageReq.clipId = clipId;
			clipImageReq.command = root.clipImageCommand(clipId);
			clipImageReq.running = true;
			return;
		}

		clipDecodeReq.clipId = clipId;
		clipDecodeReq.command = ["sh", "-c", "cliphist decode " + Shell.shellQuote(clipId) + " 2>/dev/null"];
		clipDecodeReq.running = true;
	}

	// PNG/JPEG/... bytes picked from the last "[[ binary data … fmt WxH ]]" placeholder.
	function clipImagePath(clipId) {
		return Quickshell.env("XDG_RUNTIME_DIR") + "/qs-clip-" + clipId + ".png";
	}

	function clipImageCommand(clipId) {
		const out = root.clipImagePath(clipId);

		return ["sh", "-c", "[ -s " + Shell.shellQuote(out) + " ] || { rm -f " + Shell.shellQuote(out) + " && cliphist decode " + Shell.shellQuote(clipId) + " >" + Shell.shellQuote(out) + " 2>/dev/null; }"];
	}

	function clipEntry(clipId) {
		for (let i = 0; i < root.clips.length; i++) {
			if (root.clips[i] && root.clips[i].clipId === clipId)
				return root.clips[i];
		}

		return null;
	}

	function buildClips() {
		const next = Entries.clipEntries(root.clipList, Parse.parseClipboardSources(root.clipSources));
		const keyOf = function (list) {
			return list.map(function (clip) { return clip.clipId + "|" + clip.appId; }).join("\n");
		};

		if (keyOf(next) !== keyOf(root.clips))
			root.clips = next;

		if (root.isClipboard)
			Qt.callLater(root.decodeCurrentClip);
	}

	function decodeCurrentClip() {
		if (!root.isClipboard)
			return;
		const entry = root.results[list.currentIndex >= 0 ? list.currentIndex : 0];
		if (entry && entry.clipId)
			root.decodeClip(entry.clipId);
		else
			root.decodeClip("");
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
		const target = address.indexOf("0x") === 0 ? address : "0x" + address;

		Hyprland.dispatch(Hyprland.usingLua
			? "hl.dsp.focus({ window = \"address:" + target + "\" })"
			: "focuswindow address:" + target);
	}

	function killProc(entry) {
		if (!entry || entry.kind !== "proc")
			return;

		Quickshell.execDetached(System.killCommand(entry.pid, Config.procKillSignal));
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
			Quickshell.execDetached(Apps.launchCommand(entry, entry.appId, root.terminal));
		else if (entry.kind === "window") {
			const ws = entry.workspace;
			const name = ws && ws.name ? String(ws.name) : "";
			const addr = entry.address.indexOf("0x") === 0 ? entry.address : "0x" + entry.address;
			const match = name.match(/^v?(\d+)(?:\.(\d+))?$/);

			if (match && Hyprland.usingLua) {
				const slot = parseInt(match[1], 10);
				const version = match[2] ? parseInt(match[2], 10) : 1;
				const code = "require(\"versions\").visit(" + slot + "," + version + "); hl.dispatch(hl.dsp.focus({window = \"address:" + addr + "\"}))";
				Quickshell.execDetached(["sh", "-c", "hyprctl eval '" + code + "'"]);
			} else if (match) {
				Quickshell.execDetached(["sh", "-c", "hyprctl dispatch focuswindow address:" + addr]);
			} else {
				root.pendingFocus = entry.address;
			}
		}
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

	onModeChanged: {
		list.currentIndex = 0;
		Yudae.launcherQuery(root.query, root.forced, root.group);

		if (root.mode === "wallpaper")
			root.openWallpaper();
		else if (root.mode === "clipboard") {
			clipSourcesFile.reload();
			clipsList.running = true;
		}
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
			root.clipList = Parse.parseClipboardList(text);
			root.buildClips();
		}
	}

	Request {
		id: procList

		command: ["ps", "-eo", "pcpu=,pid=,comm:16=,args=", "--sort=-pcpu"]

		function reload() {
			if (!procList.running)
				procList.running = true;
		}

		onDone: function (text) {
			root.procs = System.parseTopProcesses(text);
			root.procRows = System.holdProcessOrder(root.procRows, System.filterProcesses(root.procs, Config.psIgnore, "", Config.launcherMaxResults));
		}
	}

	Timer {
		interval: Config.cpuPollMs * 2
		running: root.shown && root.mode === "procs"
		repeat: true
		triggeredOnStart: true
		onTriggered: procList.reload()
	}

	FileView {
		id: versionsFile

		path: Quickshell.shellDir + "/cache/versions.json"
		preload: true
		watchChanges: true
		printErrors: false

		onFileChanged: versionsFile.reload()
		onLoaded: {
			const text = versionsFile.text();

			if (text === "")
				return;

			try {
				root.versions = JSON.parse(text);
			} catch (e) {
				root.versions = ({});
			}
		}
	}

	FileView {
		id: clipSourcesFile

		path: root.stateDir + "/clip-apps.txt"
		preload: true
		watchChanges: true
		printErrors: false

		onFileChanged: clipSourcesFile.reload()
		onLoaded: {
			root.clipSources = clipSourcesFile.text();
			root.buildClips();
		}
	}

	Request {
		id: clipDecodeReq

		property string clipId: ""

		command: ["sh", "-c", "cliphist decode " + Shell.shellQuote(clipId) + " 2>/dev/null"]

		onDone: function (text) {
			if (clipDecodeReq.clipId !== "" && clipDecodeReq.clipId !== root.clipPreviewId)
				return;

			root.clipPreviewText = text;
			root.clipPreviewLoading = false;

			if (typeof previewFlick !== "undefined" && previewFlick)
				previewFlick.contentY = 0;
		}
	}

	Request {
		id: clipImageReq

		property string clipId: ""

		command: ["sh", "-c", "true"]

		onDone: function (text) {
			if (clipImageReq.clipId === "" || clipImageReq.clipId !== root.clipPreviewId)
				return;

			root.clipPreviewText = "";
			root.clipPreviewPath = "file://" + root.clipImagePath(clipImageReq.clipId);
			root.clipPreviewLoading = false;
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
								visible: rowIcon.icon === "" || rowIconImage.status === Image.Error
								anchors.centerIn: parent
								font.family: Config.fontFamily
								font.pixelSize: 18
								color: row.active ? Config.launcherHighlightText : Config.foreground
								text: root.rowGlyph(row.modelData)
								z: 1
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
			entries: root.windowEntries()
			index: root.winCurrent
			title: root.winName
			emptyMessage: root.emptyText()
			available: root.screen ? root.screen.width : root.width
		}
	}
}
