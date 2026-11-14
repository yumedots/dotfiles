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
	signal wallpaperRequested()

	property bool shown: false
	property bool instant: false
	property bool keepQuery: false
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

	property bool placed: false
	property real placeX: 0
	property real placeY: 0
	property real savedX: 0
	property real savedY: 0
	property bool savedPlace: false
	property real dragX: 0
	property real dragY: 0
	property bool dragHold: false

	property bool windows: false
	property int winIndex: 0

	// The daemon says which request a snapshot answers, so the card waits for
	// the one it asked for. Fading in on whatever was there last showed the
	// previous screen until the right one arrived.
	property bool settled: false

	Timer {
		id: settleGuard

		interval: 150

		onTriggered: root.settled = true
	}

	Timer {
		id: windowDragTimer

		interval: 50

		onTriggered: root.applyWindowDrag()
	}

	readonly property var state: Yudae.launcher

	FileView {
		id: placement

		path: Quickshell.stateDir + "/launcher-position.json"
		preload: true
		printErrors: false

		onLoaded: root.loadPlace(text())
	}

	function defaultX() {
		return Math.round((root.width - card.width) / 2);
	}

	function defaultY() {
		return root.spotlight ? Math.round(root.height * Config.launcherSpotlightTop) : Math.round((root.height - card.height) / 2);
	}

	function place(x, y) {
		if (root.configured && root.width > 1 && root.height > 1 && card.width > 0 && card.height > 0) {
			root.placeX = Calc.clamp(x, 0, Math.max(0, root.width - card.width));
			root.placeY = Calc.clamp(y, 0, Math.max(0, root.height - card.height));
		} else {
			root.placeX = x;
			root.placeY = y;
		}

		root.placed = true;
	}

	function clampPlace() {
		if (!root.placed || root.width <= 1 || root.height <= 1 || card.width <= 0 || card.height <= 0)
			return;

		root.place(root.placeX, root.placeY);
	}

	function loadPlace(body) {
		try {
			const at = JSON.parse(body);

			if (typeof at.x !== "number" || typeof at.y !== "number")
				return;

			root.savedX = at.x;
			root.savedY = at.y;
			root.savedPlace = true;

			if (root.shown && !root.placed && Config.launcherMove !== "forget")
				root.place(root.savedX, root.savedY);
		} catch (error) {
		}
	}

	function savePlace() {
		if (!root.placed || Config.launcherMove === "forget")
			return;

		root.savedX = root.placeX;
		root.savedY = root.placeY;
		root.savedPlace = true;
		placement.setText(JSON.stringify({ x: Math.round(root.placeX), y: Math.round(root.placeY) }));
	}

	// A card on its way out keeps the screen it was showing. The snapshot goes
	// back to the first screen once the launcher lets go of it, and following
	// that mid-fade flashed the wrong screen on the way out.
	property string heldMode: ""
	property var heldResults: []

	property var live: ({})

	readonly property string mode: root.windows ? "windows" : (root.shown ? (root.live.mode || "apps") : (root.heldMode || root.live.mode || "apps"))
	readonly property string prompt: root.windows ? "" : (root.live.prompt || "")
	readonly property bool isClipboard: root.mode === "clipboard"
	readonly property string empty: root.windows ? Yudae.windowsEmpty : (root.live.empty || "")
	readonly property var results: root.windows ? (Yudae.windows || []) : (root.shown ? (root.live.results || []) : root.heldResults)
	readonly property var clipPages: root.state.clip && root.state.clip.pages ? root.state.clip.pages : []
	readonly property bool clipMore: root.state.clip ? root.state.clip.more === true : false
	readonly property string clipPagesId: root.state.clip ? String(root.state.clip.id || "") : ""
	property string shownId: ""
	property int moreAsked: -1

	ListModel {
		id: pageModel
	}

	function syncPages() {
		const pages = root.clipPages;

		if (root.shownId !== root.clipPagesId || pageModel.count > pages.length) {
			pageModel.clear();
			root.shownId = root.clipPagesId;
		}

		for (let i = pageModel.count; i < pages.length; i++)
			pageModel.append({ body: pages[i].text, tail: pages[i].tail });
	}

	onClipPagesChanged: root.syncPages()
	readonly property real clipTime: root.state.clip && root.state.clip.time ? root.state.clip.time : 0
	readonly property int clipWords: root.state.clip && root.state.clip.words ? root.state.clip.words : 0
	readonly property string clipPreviewPath: root.state.clip && root.state.clip.path ? "file://" + root.state.clip.path : ""

	readonly property int selectedIndex: root.results.length === 0 ? -1 : Calc.clamp(list.currentIndex < 0 ? 0 : list.currentIndex, 0, root.results.length - 1)
	readonly property var selectedRow: root.selectedIndex >= 0 ? root.results[root.selectedIndex] : null
	readonly property string wantedClip: root.shown && root.isClipboard && root.selectedRow && root.selectedRow.clipId ? root.selectedRow.clipId : ""

	readonly property int windowColumns: windowsGrid.columns
	readonly property int winCurrent: Calc.clamp(root.winIndex, 0, Math.max(0, root.results.length - 1))
	readonly property string winName: root.windows && root.results.length > 0 ? root.results[root.winCurrent].name : ""

	readonly property bool spotlight: (Config.launcherSpotlight || Config.launcherGrid) && !root.windows
	readonly property bool grid: Config.launcherGrid && !root.windows && (root.mode === "apps" || root.mode === "group:apps")
	readonly property real rowGap: root.spotlight ? 0 : Config.launcherGap
	readonly property bool home: root.forced === "" && root.group === ""
	readonly property bool revealed: root.grid || !root.spotlight || !root.home || (root.query !== "" && !!root.live.intent && root.live.intent.query !== "")
	readonly property real fontSize: root.spotlight ? Config.launcherSpotlightFontSize : Config.launcherFontSize
	readonly property real iconSize: root.spotlight ? Math.round(root.fontSize * 1.4) : Config.launcherIconSize
	readonly property real rowHeight: root.spotlight
		? (root.mode === "emoji" ? root.emojiRowHeight : root.iconSize + 12)
		: (root.mode === "emoji" ? root.emojiRowHeight : Config.launcherRowHeight)
	readonly property real emojiRowHeight: Math.round(root.iconSize + root.fontSize * 0.72 + 14)
	readonly property real iconSlot: root.spotlight ? root.iconSize + 4 : Config.launcherIconSlot
	readonly property real kaomojiSlot: Math.min(220, Math.max(120, Math.round(card.width * 0.36)))
	readonly property int maxRows: {
		const base = root.spotlight ? Config.launcherSpotlightMaxRows : Config.launcherMaxRows;

		if (root.mode !== "emoji" || !root.spotlight)
			return base;

		const top = Math.round(root.height * Config.launcherSpotlightTop);
		const room = root.height - top - Config.launcherPadding * 2 - Config.launcherSpotlightInputHeight - Config.launcherGap;

		return Calc.clamp(Math.floor(room / (root.emojiRowHeight + root.rowGap)), 1, base);
	}
	readonly property int rows: root.spotlight && !root.isClipboard ? Calc.clamp(root.results.length, 1, root.maxRows) : root.maxRows
	readonly property int listHeight: root.grid ? appGrid.implicitHeight : root.spotlight ? root.rows * root.rowHeight + (root.rows - 1) * root.rowGap : Config.launcherMaxRows * root.rowHeight
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

	Region {
		id: emptyRegion

		width: 0
		height: 0
	}

	mask: root.shown ? null : emptyRegion

	property bool alwaysMapped: false

	visible: alwaysMapped || root.shown || card.opacity > 0

	Component.onCompleted: {
		root.setWindowDrag(false);

		if (root.alwaysMapped)
			root.push();
	}

	onWidthChanged: root.clampPlace()
	onHeightChanged: root.clampPlace()
	onConfiguredChanged: root.clampPlace()

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
		root.anchorKey = root.mode + "\u0000" + (root.live.query || "");
	}

	function followResults() {
		const key = root.mode + "\u0000" + (root.live.query || "");

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

	function copiedLabel(seconds) {
		if (seconds <= 0)
			return "";

		const at = new Date(seconds * 1000);
		const now = new Date();
		const days = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(at.getFullYear(), at.getMonth(), at.getDate())) / 86400000);
		const clock = Qt.formatTime(at, Config.launcherClipTimeFormat);

		if (days <= 0)
			return "Copied Today " + clock;

		if (days === 1)
			return "Copied Yesterday " + clock;

		return "Copied " + Qt.formatDate(at, "MMM d") + " " + clock;
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

		Yudae.cmd("launcher", { query: root.query, forced: root.forced, group: root.group, all: Config.launcherGrid });
	}

	function setWindowDrag(hold) {
		root.dragHold = hold;
		windowDragTimer.restart();
	}

	function applyWindowDrag() {
		Quickshell.execDetached(["hyprctl", "eval", "require('binds').launcherDrag(" + (root.dragHold ? "true" : "false") + ")"]);
	}

	function open(mode) {
		root.instant = false;

		if (mode !== undefined)
			root.windows = false;

		root.setWindowDrag(true);

		if (root.keepQuery)
			root.keepQuery = false;
		else
			root.query = "";
		root.group = "";
		root.forced = mode || "";
		root.pointer = null;
		root.live = ({});
		root.anchorId = "";
		root.anchorKey = "";
		root.freshAnchor = true;
		list.currentIndex = 0;
		field.typing = !root.windows && (root.spotlight || root.forced === "");

		// The window switcher reads the window list rather than the launcher
		// snapshot, so it has nothing to wait for.
		root.settled = root.windows;
		settleGuard.restart();

		root.placed = Config.launcherMove !== "forget" && root.savedPlace;

		if (root.placed) {
			root.placeX = root.savedX;
			root.placeY = root.savedY;
			root.clampPlace();
		}

		root.shown = true;
		root.winIndex = root.windows ? 1 : 0;
		root.grabbed = false;
		root.push();

		if (root.syncLive())
			settleGuard.stop();

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

	function hideInstant() {
		root.instant = true;
		root.keepQuery = true;
		root.close();
	}

	function close() {
		root.setWindowDrag(false);
		root.heldMode = root.mode;
		root.heldResults = root.results;
		root.shown = false;
		root.anchorId = "";
		root.anchorKey = "";
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

	function altPick(event) {
		const n = event.key - Qt.Key_0;

		if (!(event.modifiers & Qt.AltModifier) || n < 1 || n > 9 || n > root.rows)
			return false;

		const at = list.firstVisible + n - 1;

		if (at >= root.results.length)
			return false;

		root.activate(root.results[at]);
		event.accepted = true;
		return true;
	}

	function handleKeys(event) {
		if (root.windows) {
			Input.switcher(event, root);
			return;
		}

		if (root.altPick(event))
			return;

		if ((root.mode === "procs" || root.mode === "vms") && event.text === Config.procKillKey) {
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
			const picked = root.pickedText();

			if (picked !== "") {
				Yudae.cmd("launcher", { copyText: picked });
				root.grab();
				event.accepted = true;
				return;
			}
		}

		if (root.isClipboard) {
			const page = Math.max(1, previewFlick.height - root.rowHeight);
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

		if (root.altPick(event))
			return;

		if ((root.mode === "procs" || root.mode === "vms") && event.key === Qt.Key_Delete) {
			root.killProc(root.selectedRow);
			event.accepted = true;
			return;
		}

		if (root.isClipboard && (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)) {
			root.scrollPreview((event.key === Qt.Key_PageDown ? 1 : -1) * Math.max(1, previewFlick.height - root.rowHeight));
			event.accepted = true;
			return;
		}

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
		const step = Input.axis(dir, appGrid.columns, 1);

		if (root.grid && step !== 0) {
			list.currentIndex = Calc.clamp(list.currentIndex + step, 0, root.results.length - 1);
			return true;
		}

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
		field.typing = true;
		list.currentIndex = 0;
		root.push();
	}

	function saveQuery() {
		if (root.query === "" || root.windows)
			return;

		Yudae.cmd("launcher", { save: root.query });
	}

	function openWallpaper() {
		root.hideInstant();
		root.wallpaperRequested();
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

	function hover(index, at) {
		const prev = root.pointer;

		if (!prev) {
			root.pointer = { x: at.x, y: at.y, engaged: false };
			return;
		}

		if (prev.engaged || (at.x - prev.x) ** 2 + (at.y - prev.y) ** 2 >= root.rowHeight ** 2) {
			root.pointer = { x: at.x, y: at.y, engaged: true };

			if (at.x !== prev.x || at.y !== prev.y)
				list.currentIndex = index;
		}
	}

	function copyClip(id) {
		Yudae.cmd("launcher", { copyClip: id });
		root.grab();
	}

	property var pickFrom: null
	property var pickTo: null
	property point pickAt: Qt.point(0, 0)

	function pickPoint(x, y) {
		const count = pageList.count;

		if (count === 0)
			return null;

		const at = pageColumn.mapFromItem(previewCatcher, x, y);

		let index = 0;

		for (let i = 0; i < count; i++) {
			if (pageList.itemAt(i).y <= at.y)
				index = i;
		}

		const page = pageList.itemAt(index);
		const pos = at.y >= page.y + page.height ? page.length : page.positionAt(Calc.clamp(at.x - page.x, 0, page.width), Math.max(0, at.y - page.y));

		return { page: index, pos: pos };
	}

	function pickApply() {
		const a = root.pickFrom;
		const b = root.pickTo;

		if (!a || !b)
			return;

		const forward = a.page < b.page || (a.page === b.page && a.pos <= b.pos);
		const lo = forward ? a : b;
		const hi = forward ? b : a;

		for (let i = 0; i < pageList.count; i++) {
			const page = pageList.itemAt(i);

			if (i < lo.page || i > hi.page)
				page.deselect();
			else
				page.select(i === lo.page ? lo.pos : 0, i === hi.page ? hi.pos : page.length);
		}
	}

	function pickClear() {
		for (let i = 0; i < pageList.count; i++)
			pageList.itemAt(i).deselect();

		root.pickFrom = null;
		root.pickTo = null;
	}

	function pickedText() {
		let out = "";
		let last = -1;

		for (let i = 0; i < pageList.count; i++) {
			if (pageList.itemAt(i).selectedText !== "")
				last = i;
		}

		for (let i = 0; i < pageList.count; i++) {
			const page = pageList.itemAt(i);

			if (page.selectedText === "")
				continue;

			out += page.selectedText + (i < last ? page.tail : "");
		}

		return out;
	}

	function loadMore() {
		if (!root.clipMore || root.moreAsked === root.clipPages.length)
			return;

		if (previewFlick.contentY + previewFlick.height * 3 < previewFlick.contentHeight)
			return;

		root.moreAsked = root.clipPages.length;
		Yudae.cmd("launcher", { clipMore: true });
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
		if (entry && entry.kind === "proc")
			Yudae.cmd("launcher", { kill: entry.pid });
		else if (entry && entry.kind === "vm")
			Yudae.cmd("launcher", { killVm: entry.id });
	}

	function activate(entry) {
		if (!entry)
			return;

		if (entry.kind === "mode") {
			if (entry.mode === "vms") {
				root.close();
				Yudae.vmsCommand("app", {});
				return;
			}

			if (entry.mode === "disk") {
				root.close();
				Yudae.diskCommand("app", {});
				return;
			}

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

	function syncLive() {
		const intent = root.state.intent;

		if (root.windows || !root.shown || !intent)
			return false;

		if (intent.query !== root.query || intent.forced !== root.forced || intent.group !== root.group)
			return false;

		root.live = root.state;
		root.settled = true;
		settleGuard.stop();
		return true;
	}

	onStateChanged: {
		if (root.windows || !root.shown)
			return;

		if (!root.syncLive())
			root.push();
	}

	onWantedClipChanged: {
		root.moreAsked = -1;
		root.requestClip();
	}

	onResultsChanged: root.followResults()

	onModeChanged: {
		list.currentIndex = 0;
		list.reset();
		appGrid.reset();

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

		x: root.placed ? root.placeX : root.defaultX()
		y: root.placed ? root.placeY : root.defaultY()

		width: root.windows ? windowsGrid.implicitWidth + card.inset * 2
		      : root.grid ? appGrid.implicitWidth + card.inset * 2
		      : root.spotlight ? Config.launcherSpotlightWidth
		      : root.isClipboard ? Config.launcherWidth * 2 + Config.launcherGap + card.inset * 2
		      : Config.launcherWidth
		height: root.windows ? windowsGrid.implicitHeight + card.inset * 2 : column.implicitHeight + card.inset * 2 - (root.spotlight && root.revealed ? Config.launcherPadding : 0)
		padding: Config.launcherPadding
		backgroundColor: Config.surfaceTranslucent
		opacity: root.shown && root.settled ? 1 : 0
		visible: root.configured && (root.shown || opacity > 0)

		onWidthChanged: root.clampPlace()
		onHeightChanged: root.clampPlace()

		Behavior on opacity {
			enabled: !root.instant

			NumberAnimation { duration: Config.popupFadeMs; easing.type: Easing.OutCubic }
		}
		focus: true

		onOpacityChanged: {
			if (opacity !== 0 || root.instant)
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
				boxHeight: root.spotlight ? Config.launcherSpotlightInputHeight : Config.launcherInputHeight
				hintKey: root.spotlight ? "" : Config.procHintKey
				hintText: Config.procSearchHint
				padding: 0
				gap: root.spotlight ? 0 : Config.launcherTextGap
				glyphSlot: root.spotlight ? 0 : root.iconSlot
				glyphSize: root.iconSize
				size: root.spotlight ? Config.launcherSpotlightQuerySize : root.fontSize
				glyph: root.spotlight ? "" : root.prompt
				boxColor: root.spotlight ? "transparent" : Config.launcherSearchBox

				onEdited: {
					root.query = field.text;
					list.currentIndex = 0;
				}
				onAccepted: root.activate(root.selectedRow)
				onKeyPressed: function (event) { root.handleTypingKeys(event); }
				onTypingChanged: {
					if (field.typing || !root.shown)
						return;

					if (!root.spotlight && !root.home) {
						card.forceActiveFocus();
						return;
					}

					if (root.group !== "")
						root.leaveGroup();
					else
						root.close();
				}
			}

			// ── results pane: clipboard preview + list ────────────────────
			Item {
				width: parent.width
				height: root.listHeight
				visible: root.revealed

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
						anchors.bottomMargin: Config.launcherTextGap + copiedCaption.height
						visible: root.clipPreviewPath === ""
						clip: true
						contentWidth: width
						contentHeight: pageColumn.height
						boundsBehavior: Flickable.StopAtBounds
						interactive: false

						onContentYChanged: root.loadMore()
						onContentHeightChanged: root.loadMore()

						Column {
							id: pageColumn

							width: previewFlick.width

							Repeater {
								id: pageList

								model: pageModel

								TextEdit {
									required property string body
									required property string tail

									width: pageColumn.width
									readOnly: true
									selectByMouse: false
									selectByKeyboard: false
									activeFocusOnPress: false
									persistentSelection: true
									cursorVisible: false
									wrapMode: TextEdit.Wrap
									font.family: Config.fontFamily
									font.pixelSize: Config.fontSize
									color: Config.foreground
									text: body
									textFormat: TextEdit.PlainText
									selectionColor: Config.launcherHighlight
									selectedTextColor: Config.launcherHighlightText
								}
							}
						}

					}

					MouseArea {
						id: previewCatcher

						anchors.fill: previewFlick
						visible: previewFlick.visible
						acceptedButtons: Qt.LeftButton

						function extend(x, y) {
							root.pickTo = root.pickPoint(x, y);
							root.pickApply();
						}

						onPressed: function (mouse) {
							root.pickClear();
							root.pickFrom = root.pickPoint(mouse.x, mouse.y);
							root.pickAt = Qt.point(mouse.x, mouse.y);
						}

						onPositionChanged: function (mouse) {
							root.pickAt = Qt.point(mouse.x, mouse.y);
							previewCatcher.extend(mouse.x, mouse.y);
						}

						onWheel: function (wheel) {
							root.scrollPreview(wheel.angleDelta.y > 0 ? -root.rowHeight : root.rowHeight);
							wheel.accepted = true;
						}

						Timer {
							interval: 30
							repeat: true
							running: previewCatcher.pressed && (root.pickAt.y < 0 || root.pickAt.y > previewCatcher.height)

							onTriggered: {
								root.scrollPreview(root.pickAt.y < 0 ? -root.rowHeight : root.rowHeight);
								previewCatcher.extend(root.pickAt.x, root.pickAt.y);
							}
						}
					}

					// image clips mirror the wallpaper preview mechanics
					Image {
						id: clipShot

						anchors.fill: parent
						anchors.margins: Config.launcherTextGap
						anchors.bottomMargin: Config.launcherTextGap + copiedCaption.height
						visible: root.clipPreviewPath !== ""
						fillMode: Image.PreserveAspectFit
						cache: true
						asynchronous: true
						retainWhileLoading: true
						source: root.clipPreviewPath === "" ? "" : root.clipPreviewPath
					}

					Column {
						id: copiedCaption

						anchors.left: parent.left
						anchors.right: parent.right
						anchors.bottom: parent.bottom
						anchors.bottomMargin: Config.launcherTextGap

						Repeater {
							model: [root.clipWords > 0 ? root.clipWords + (root.clipWords === 1 ? " word" : " words") : "", root.copiedLabel(root.clipTime)]

							Text {
								required property string modelData

								width: copiedCaption.width
								height: modelData === "" ? 0 : implicitHeight
								horizontalAlignment: Text.AlignHCenter
								elide: Text.ElideRight
								font.family: Config.fontFamily
								font.pixelSize: Config.fontSize
								color: Config.muted
								text: modelData
							}
						}
					}
				}
				// left pane: the results list
				Item {
					id: listPane

					anchors.left: parent.left
					anchors.leftMargin: -Config.launcherPadding
					anchors.right: root.isClipboard ? previewPane.left : parent.right
					anchors.rightMargin: root.isClipboard ? Config.launcherGap : -Config.launcherPadding
					anchors.top: parent.top
					anchors.bottom: parent.bottom

					Selector {
						id: list

						readonly property int firstVisible: Math.round(list.offset / (list.rowHeight + list.rowSpacing))

						anchors.fill: parent
						visible: root.results.length > 0 && !root.grid
						visibleRows: root.rows
						scrollWidth: root.spotlight ? 0 : Config.scrollbarWidth
						highlightRadius: 0
						rowHeight: root.rowHeight
						rowSpacing: root.rowGap
						model: root.grid ? [] : root.results

						delegate: Item {
							id: row

							required property var modelData
							required property int index

							width: list.width
							height: root.rowHeight

							readonly property bool active: row.index === list.currentIndex
							readonly property bool pinned: row.modelData.pinned === true
							readonly property bool wide: row.modelData.kind === "kaomoji"

							Item {
								id: rowIcon

								anchors.left: parent.left
								anchors.leftMargin: Config.launcherPadding
								anchors.verticalCenter: parent.verticalCenter
								width: row.wide ? root.kaomojiSlot : root.iconSlot
								height: root.iconSlot

							readonly property string icon: row.modelData.kind === "proc" ? AppIcons.iconOfPid(row.modelData.pid) : (row.modelData.appId ? AppIcons.iconOf(row.modelData.appId) : "")

							Text {
								visible: row.modelData.kind !== "app" && (rowIcon.icon === "" || rowIconImage.status === Image.Error)
								x: row.wide ? 0 : (parent.width - width) / 2
								y: (parent.height - height) / 2
								width: row.wide ? parent.width : implicitWidth
								horizontalAlignment: Text.AlignLeft
								wrapMode: Text.NoWrap
								elide: Text.ElideNone
								fontSizeMode: row.wide ? Text.Fit : Text.FixedSize
								minimumPixelSize: 8
								font.family: Config.fontFamily
								font.pixelSize: root.iconSize
								color: row.active ? Config.launcherHighlightText : Config.foreground
								text: row.modelData.glyph
								z: 1
							}

							Rectangle {
								anchors.centerIn: parent
								width: root.iconSize
								height: root.iconSize
								radius: Config.rowRadius
								color: Config.surface
								visible: row.modelData.kind === "app" && (rowIcon.icon === "" || rowIconImage.status === Image.Error)
							}

							AppIcon {
								id: rowIconImage

								anchors.centerIn: parent
								implicitSize: root.iconSize
								visible: rowIcon.icon !== ""
								source: rowIcon.icon
								z: 2
							}
							}

							Column {
								id: rowText

								anchors.left: rowIcon.right
								anchors.leftMargin: Config.launcherTextGap
								anchors.right: rowUsage.left
								anchors.rightMargin: Config.launcherTextGap
								anchors.verticalCenter: parent.verticalCenter

								Text {
									id: rowName

									width: parent.width
									elide: Text.ElideRight
									font.family: Config.fontFamily
									font.pixelSize: root.fontSize
									color: row.active ? Config.launcherHighlightText : Config.foreground
									text: row.modelData.name
								}

								Text {
									id: rowHint

									width: parent.width
									visible: root.mode === "emoji"
									elide: Text.ElideRight
									font.family: Config.fontFamily
									font.pixelSize: Math.round(root.fontSize * 0.72)
									color: Config.muted
									text: "click to copy to clipboard"
								}
							}

							Text {
								id: rowAlt

								readonly property int slot: row.index - list.firstVisible + 1

								anchors.right: parent.right
								anchors.rightMargin: Config.launcherPadding * 2
								anchors.verticalCenter: parent.verticalCenter
								width: visible ? implicitWidth : 0
								visible: !row.active && slot >= 1 && slot <= 9 && slot <= root.rows
								font.family: Config.fontFamily
								font.pixelSize: Math.round(root.fontSize * 0.8)
								color: row.active ? Config.launcherHighlightText : Config.muted
								text: "Alt" + slot
							}

							Glyph {
								id: rowSelect

								anchors.right: parent.right
								anchors.rightMargin: Config.launcherPadding * 2 + (rowAlt.implicitWidth - width) / 2
								anchors.verticalCenter: parent.verticalCenter
								width: visible ? implicitWidth : 0
								visible: row.active
								size: Math.round(root.iconSize * 0.75)
								color: Config.launcherHighlightText
								glyph: Config.launcherIconSelect
							}

							Text {
								id: rowUsage

								anchors.right: row.active ? rowSelect.left : rowAlt.left
								anchors.rightMargin: Config.launcherTextGap
								anchors.verticalCenter: parent.verticalCenter
								width: visible ? implicitWidth : 0
								visible: row.modelData.kind === "proc" || row.modelData.kind === "vm"
								font.family: Config.fontFamily
								font.pixelSize: root.fontSize
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
								font.pixelSize: root.iconSize
								color: Config.foreground
								text: Config.launcherIconPin
							}
							HoverHandler {
								onPointChanged: {
									if (!hovered)
										return;

									root.hover(row.index, point.scenePosition);
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

					AppGrid {
						id: appGrid

						anchors.fill: parent
						visible: root.grid && root.results.length > 0
						results: root.grid ? root.results : []
						currentIndex: root.selectedIndex

						onHovered: function (index, at) { root.hover(index, at); }
						onClicked: function (index) {
							list.currentIndex = index;
							root.activate(root.results[index]);
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
							font.pixelSize: root.fontSize
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

		DragHandler {
			target: null
			acceptedButtons: Qt.LeftButton
			acceptedModifiers: Qt.MetaModifier
			grabPermissions: PointerHandler.CanTakeOverFromAnything

			onActiveChanged: {
				if (active) {
					root.dragX = card.x;
					root.dragY = card.y;
					root.place(root.dragX, root.dragY);
					return;
				}

				root.savePlace();
			}

			onActiveTranslationChanged: {
				if (active)
					root.place(root.dragX + activeTranslation.x, root.dragY + activeTranslation.y);
			}
		}
	}
}
