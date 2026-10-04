import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.ui
import qs
import qs.services

PanelWindow {
	id: root

	property bool shown: false
	property string query: ""
	property var pins: []
	property string terminal: ""
	property var usage: ({})
	property var saved: []
	property string group: ""
	property string forced: ""
	property var pending: null
	property var wallpapers: []
	property string wallpaperDir: ""
	property string listing: ""
	property var warm: []
	property string warmPath: ""
	property string activeWallpaper: ""

	readonly property int windowColumns: windowsGrid.columns
	readonly property int winCurrent: Util.clamp(root.winIndex, 0, Math.max(0, root.results.length - 1))
	readonly property string winName: root.windows && root.results.length > 0 ? root.results[root.winCurrent].name : ""
	property var clips: []
	property bool windows: false
	property int winIndex: 0
	property string pendingFocus: ""

	readonly property var prefix: Apps.detectPrefix(root.query, Entries.modeMarks(Config.launcherModes))
	readonly property string search: root.windows || root.group !== "" || root.forced !== "" ? root.query : root.prefix.text
	readonly property string mode: root.windows ? "windows" : (root.group !== "" ? "group:" + root.group : (root.forced !== "" ? root.forced : root.prefix.mode))
	readonly property string home: Quickshell.env("HOME")
	readonly property string terminalConfig: Config.launcherTerminalConfig.replace("~", root.home)
	readonly property string stateDir: Quickshell.shellDir + "/cache/launcher"
	readonly property string settingsPath: Quickshell.shellDir + "/cache/settings.lua"
	readonly property string thumbDir: Quickshell.shellDir + "/cache/wallpapers"
	readonly property var held: root.mode === "wallpaper" ? root.results[list.currentIndex] : null
	readonly property string shotPath: root.held && root.held.kind === "wallpaper" ? root.held.preview : ""
	readonly property var appEntries: Entries.appEntries(AppIcons.entries, Config.launcherIgnoreApps, Config.launcherAppAliases)
	readonly property var results: Apps.results(root.mode, root.search, {
		clips: root.clips,
		windows: root.windowEntries(),
		entries: Entries.all(Config, root.appEntries, root.saved),
		groups: ({ apps: root.appEntries }),
		pins: root.pins,
		usage: root.usage,
		calc: Parse.calcEntry(root.search),
		wallpapers: root.wallpapers
	})
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

	visible: root.shown || card.opacity > 0

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

			root.focusWindow(root.pendingFocus);
		}
	}

	function open() {
		root.query = "";
		root.pendingFocus = "";
		root.clips = [];
		root.group = "";
		root.forced = "";
		Hyprland.refreshToplevels();
		pinsFile.running = true;
		usageFile.running = true;
		terminalFile.running = true;
		savedFile.running = true;
		settingsFile.running = true;
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
		const values = Apps.realWindows(Hyprland.toplevels.values ? Hyprland.toplevels.values : []);

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
		if (root.mode === "wallpaper")
			return Config.wallpaperEmpty;
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

	function listWallpapers(dir) {
		const path = String(dir || "").replace(/^~/, root.home);
		const prune = ["node_modules", ".git"].map(function (name) { return "-name " + Shell.shellQuote(name); }).join(" -o ");
		const images = Shell.shellQuote("\\.(jpg|jpeg|png|webp|gif|bmp|avif)$");

		return ["sh", "-c", "find " + Shell.shellQuote(path) + " -maxdepth " + Config.wallpaperDepth
			+ " \\( " + prune + " \\) -prune -o -type f -print 2>/dev/null | grep -iE " + images + " | sort"];
	}

	function saveWallpaper(image) {
		if (root.wallpaperDir === "")
			return;

		root.writeFile(root.settingsPath, Wallpaper.settingsText(image, root.wallpaperDir));
	}

	function rememberThumb() {
		const entry = root.held;

		if (!entry || entry.kind !== "wallpaper" || entry.preview !== entry.path)
			return;

		grabThumb(shot, entry.path, false);
	}

	function grabThumb(item, path, next) {
		const ratio = root.screen ? root.screen.devicePixelRatio : 1;

		if (item.width < 1 || item.height < 1) {
			if (next) {
				root.warmPath = "";
				root.warmNext();
			}

			return;
		}

		item.grabToImage(function (grab) {
			grab.saveToFile(Wallpaper.thumbPath(path, root.thumbDir));

			if (!next)
				return;

			root.warmPath = "";
			root.warmNext();
		}, Qt.size(item.width * ratio, item.height * ratio));
	}

	function warmNext() {
		if (root.warmPath !== "")
			return;

		while (root.warm.length > 0) {
			const path = root.warm[0];

			root.warm = root.warm.slice(1);

			if (root.held !== null && root.held.path === path)
				continue;

			root.warmPath = path;
			warmer.source = "file://" + path;
			return;
		}

		root.warmPath = "";
		warmer.source = "";
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
			root.pendingFocus = entry.address;
		else if (entry.kind === "command" || entry.kind === "action" || entry.kind === "saved")
			Quickshell.execDetached(["sh", "-c", entry.command]);
		else if (entry.kind === "calc")
			root.copy(entry.value);
		else if (entry.kind === "clip")
			root.copyClip(entry.clipId);
		else if (entry.kind === "file")
			Quickshell.execDetached(["xdg-open", entry.path]);
		else if (entry.kind === "wallpaper") {
			Quickshell.execDetached(Wallpaper.applyCommand(entry.path, Config));
			root.saveWallpaper(entry.path);
		}

		root.pending = entry;
		root.close();
	}

	onModeChanged: {
		if (root.mode === "clipboard")
			clipsList.running = true;
		else if (root.mode === "wallpaper")
			root.warmNext();
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
		id: settingsFile

		command: ["sh", "-c", "cat " + Shell.shellQuote(root.settingsPath) + " 2>/dev/null"]

		onDone: function (text) {
			root.wallpaperDir = Wallpaper.dirFromText(text) || Config.wallpaperDir;
			root.activeWallpaper = Wallpaper.wallpaperFromText(text) || "";
			wallpapersFile.command = root.listWallpapers(root.wallpaperDir);
			wallpapersFile.running = true;
		}
	}

	Request {
		id: wallpapersFile

		command: ["sh", "-c", "true"]

		onDone: function (text) {
			root.listing = text;
			root.wallpapers = Wallpaper.entries(text);
			thumbsFile.command = ["sh", "-c", "mkdir -p " + Shell.shellQuote(root.thumbDir) + " && ls " + Shell.shellQuote(root.thumbDir)];
			thumbsFile.running = true;
		}
	}

	Request {
		id: thumbsFile

		command: ["sh", "-c", "true"]

		onDone: function (text) {
			root.wallpapers = Wallpaper.entries(root.listing, root.thumbDir, Wallpaper.thumbsFromText(text));
			root.warm = root.wallpapers.filter(function (entry) { return entry.preview === entry.path; }).map(function (entry) { return entry.path; });
			root.warmNext();
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
		opacity: root.shown ? 1 : 0
		visible: root.configured && (root.shown || opacity > 0)
		focus: true

		Behavior on opacity {
			NumberAnimation { duration: Config.popupFadeMs; easing.type: Easing.OutCubic }
		}

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

			Item {
				id: preview

				width: parent.width
				height: visible ? Config.wallpaperPreviewHeight : 0
				visible: root.shotPath !== ""
				clip: true

				Image {
					id: warmer

					width: parent.width
					height: Config.wallpaperPreviewHeight
					opacity: 0.001
					fillMode: Image.PreserveAspectCrop
					cache: true
					asynchronous: true
					retainWhileLoading: true
					sourceSize.width: Config.wallpaperPreviewWidth
					onStatusChanged: {
						if (status === Image.Ready && root.warmPath !== "")
							root.grabThumb(warmer, root.warmPath, true);
					}
				}

				Image {
					id: shot

					anchors.fill: parent
					fillMode: Image.PreserveAspectCrop
					cache: true
					asynchronous: true
					retainWhileLoading: true
					sourceSize.width: Config.wallpaperPreviewWidth
					source: root.shotPath === "" ? "" : "file://" + root.shotPath
				onStatusChanged: {
					if (status === Image.Ready)
						root.rememberThumb();
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
					readonly property bool pinned: root.pins.indexOf(row.modelData.id) >= 0 || row.modelData.kind === "saved"
					readonly property bool current: row.modelData.kind === "wallpaper" && row.modelData.path === root.activeWallpaper

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
						id: rowMark

						anchors.right: rowPin.left
						anchors.rightMargin: row.current ? Config.launcherTextGap : 0
							anchors.verticalCenter: parent.verticalCenter
							width: row.current ? implicitWidth : 0
							visible: row.current
							font.family: Config.fontFamily
							font.pixelSize: Config.launcherIconSize
							color: row.active ? Config.launcherHighlightText : Config.muted
							text: Config.launcherIconActive
						}

						Text {
						anchors.left: rowIcon.right
						anchors.leftMargin: Config.launcherTextGap
						anchors.right: rowMark.left
						anchors.rightMargin: row.current ? 0 : Config.launcherTextGap
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
						property point origin: Qt.point(0, 0)

						onPointChanged: {
							if (!hovered)
								return;

							const at = point.scenePosition;

							if (at.x === origin.x && at.y === origin.y)
								return;

							origin = Qt.point(at.x, at.y);
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
				model: root.windows ? root.results : []

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
