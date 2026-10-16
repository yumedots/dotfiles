import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.ui

PanelWindow {
	id: root

	property bool shown: false
	property bool active: true
	property bool alwaysMapped: false

	property string wallpaperDir: ""
	property string activeWallpaper: ""
	property string listing: ""
	property var wallpapers: []
	property int currentIndex: 0
	property bool refreshing: false
	property var pointer: null

	readonly property string home: Quickshell.env("HOME")
	readonly property string settingsPath: Quickshell.shellDir + "/cache/settings.lua"
	readonly property string thumbDir: Quickshell.shellDir + "/cache/wallpapers"
	readonly property var held: root.currentIndex >= 0 && root.currentIndex < root.wallpapers.length ? root.wallpapers[root.currentIndex] : null
	readonly property string shotPath: root.held === null ? "" : root.held.path
	readonly property int columns: Math.max(1, Config.wallpaperColumns)
	readonly property real heroWidth: Config.wallpaperStageWidth
	readonly property real heroHeight: Math.round(root.heroWidth / Config.wallpaperPreviewRatio)
	readonly property real loaderWidth: Math.round(root.heroWidth * (root.screen ? root.screen.devicePixelRatio : 1))
	readonly property real shelfWidth: Config.wallpaperPickerWidth - Config.wallpaperStageWidth - Config.wallpaperSectionGap
	readonly property real gridWidth: root.shelfWidth - Config.scrollbarWidth - Config.wallpaperTileGap
	readonly property real cell: root.gridWidth / root.columns
	readonly property real tileWidth: Math.max(1, root.cell - Config.wallpaperTileGap)
	readonly property real tileHeight: Math.max(1, Math.round(root.tileWidth / Config.wallpaperPreviewRatio))
	readonly property real contentHeight: root.heroHeight
	readonly property bool configured: root.screen !== null && root.width === root.screen.width && root.height > 1

	anchors.top: true
	anchors.left: true
	anchors.bottom: true
	anchors.right: true

	implicitWidth: root.screen ? root.screen.width : 1
	implicitHeight: root.screen ? root.screen.height : 1

	exclusiveZone: -1
	color: "transparent"

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "wallpaper"
	WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
	WlrLayershell.focusable: true

	visible: root.alwaysMapped || root.shown || card.opacity > 0

	Region {
		id: emptyRegion

		width: 0
		height: 0
	}

	mask: root.shown ? null : emptyRegion

	Component.onCompleted: root.reload()

	onCurrentIndexChanged: root.reveal()

	function reveal() {
		if (root.currentIndex >= 0 && grid.count > 0)
			grid.positionViewAtIndex(root.currentIndex, GridView.Contain);
	}

	function selectActive() {
		const index = root.wallpapers.map(function (entry) { return entry.path; }).indexOf(root.activeWallpaper);

		root.currentIndex = index >= 0 ? index : 0;
		Qt.callLater(root.reveal);
	}

	function move(step) {
		if (root.wallpapers.length === 0)
			return;

		root.currentIndex = Util.clamp(root.currentIndex + step, 0, root.wallpapers.length - 1);
		root.reveal();
	}

	function open() {
		root.shown = true;
		root.pointer = null;

		if (root.wallpapers.length === 0)
			root.reload();

		Qt.callLater(function () { card.forceActiveFocus(); });
	}

	function close() {
		root.shown = false;
	}

	function toggle() {
		if (root.shown)
			root.close();
		else
			root.open();
	}

	function reload() {
		if (!root.active || settingsFile.running)
			return;

		settingsFile.running = true;
	}

	function listWallpapers(dir) {
		const path = String(dir || "").replace(/^~/, root.home);
		const prune = ["node_modules", ".git"].map(function (name) { return "-name " + Shell.shellQuote(name); }).join(" -o ");
		const images = Shell.shellQuote("\\.(jpg|jpeg|png|webp|gif|bmp|avif)$");

		return ["sh", "-c", "find " + Shell.shellQuote(path) + " -maxdepth " + Config.wallpaperDepth
			+ " \\( " + prune + " \\) -prune -o -type f -print 2>/dev/null | grep -iE " + images + " | sort"];
	}

	function applyCurrent() {
		if (root.held === null)
			return;

		Quickshell.execDetached(Wallpaper.applyCommand(root.held.path, Config, BarInk.bandPx()));
		root.saveWallpaper(root.held.path);
		root.close();
	}

	function saveWallpaper(image) {
		if (root.wallpaperDir === "")
			return;

		root.activeWallpaper = image;
		root.writeFile(root.settingsPath, Wallpaper.settingsText(image, root.wallpaperDir));
	}

	function writeFile(path, text) {
		Quickshell.execDetached(Shell.writeCommand(path, text));
	}

	function thumbCommand(missing) {
		const size = root.heroWidth + "x" + root.heroHeight;
		const jobs = missing.map(function (entry) {
			return "magick " + Shell.shellQuote(entry.path) + " -resize " + size + "^ -gravity center -extent " + size
				+ " -quality " + Config.wallpaperThumbQuality + " " + Shell.shellQuote(Wallpaper.thumbPath(entry.path, root.thumbDir));
		});

		return ["sh", "-c", "mkdir -p " + Shell.shellQuote(root.thumbDir)
			+ " && printf '%s\\n' " + jobs.map(Shell.shellQuote).join(" ")
			+ " | xargs -d '\\n' -P " + Config.wallpaperThumbJobs + " -I JOB sh -c JOB 2>/dev/null"];
	}

	function buildThumbs() {
		const missing = root.wallpapers.filter(function (entry) { return entry.preview === entry.path; });

		if (missing.length === 0)
			return;

		thumbsJob.command = root.thumbCommand(missing);
		thumbsJob.running = true;
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

			if (root.refreshing) {
				root.refreshing = false;
				return;
			}

			root.selectActive();
			root.buildThumbs();
		}
	}

	Request {
		id: thumbsJob

		command: ["sh", "-c", "true"]

		onDone: function () {
			root.refreshing = true;
			thumbsFile.running = true;
		}
	}

	Rectangle {
		id: scrim

		anchors.fill: parent
		color: Config.surface
		opacity: root.shown ? Config.wallpaperScrim : 0

		Behavior on opacity {
			NumberAnimation {
				duration: Config.wallpaperScrimMs
				easing.type: Easing.OutCubic
			}
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
		width: Config.wallpaperPickerWidth + card.inset * 2
		height: root.contentHeight + card.inset * 2
		padding: Config.wallpaperPickerPadding
		backgroundColor: Config.surfaceTranslucent
		opacity: root.shown ? 1 : 0
		visible: root.configured && (root.shown || opacity > 0)
		focus: true

		Behavior on opacity {
			NumberAnimation {
				duration: Config.wallpaperScrimMs
				easing.type: Easing.OutCubic
			}
		}

		Keys.onPressed: function (event) {
			Input.wallpaper(event, root);
		}

		Row {
			id: layout

			width: parent.width
			height: parent.height
			spacing: Config.wallpaperSectionGap

			Item {
				id: stage

				width: root.heroWidth
				height: layout.height

				Rectangle {
					id: hero

					width: parent.width
					height: root.heroHeight
					clip: true
					color: Config.launcherSearchBox

					Image {
						id: heroShot

						anchors.fill: parent
						fillMode: Image.PreserveAspectCrop
						cache: true
						asynchronous: true
						retainWhileLoading: true
						opacity: status === Image.Ready ? 1 : 0
						sourceSize.width: root.loaderWidth
						source: root.shotPath === "" ? "" : "file://" + root.shotPath

						Behavior on opacity {
							NumberAnimation {
								duration: Config.wallpaperFadeMs
								easing.type: Easing.OutCubic
							}
						}
					}

					Text {
						anchors.centerIn: parent
						visible: root.shotPath === ""
						font.family: Config.fontFamily
						font.pixelSize: Config.wallpaperNameSize
						color: Config.muted
						text: Config.wallpaperEmpty
					}
				}
			}

			Item {
				id: shelf

				width: root.shelfWidth
				height: layout.height

				GridView {
					id: grid

					anchors.left: parent.left
					anchors.right: parent.right
					anchors.rightMargin: Config.scrollbarWidth + Config.wallpaperTileGap
					anchors.top: parent.top
					anchors.topMargin: -Math.round(Config.wallpaperTileGap / 2)
					anchors.bottom: parent.bottom

					clip: true
					interactive: false
					boundsBehavior: Flickable.StopAtBounds
					keyNavigationEnabled: false
					cellWidth: root.cell
					cellHeight: root.tileHeight + Config.wallpaperTileGap
					model: root.wallpapers

					onModelChanged: Qt.callLater(root.reveal)

					delegate: Item {
						id: cell

						required property var modelData
						required property int index

						readonly property bool current: cell.index === root.currentIndex
						readonly property bool applied: cell.modelData.path === root.activeWallpaper

						width: grid.cellWidth
						height: grid.cellHeight
						z: cell.current ? 1 : 0

						Rectangle {
							id: tile

							x: Math.round((cell.width - root.tileWidth) / 2)
							y: Math.round((cell.height - root.tileHeight) / 2)
							width: root.tileWidth
							height: root.tileHeight
							color: Config.launcherSearchBox
							scale: cell.current ? Config.wallpaperHoverScale : 1

							Behavior on scale {
								NumberAnimation {
									duration: Config.wallpaperFadeMs
									easing.type: Easing.OutCubic
								}
							}

							Image {
								id: thumb

								anchors.fill: parent
								fillMode: Image.PreserveAspectCrop
								cache: true
								asynchronous: true
								retainWhileLoading: true
								opacity: cell.current ? 1 : Config.wallpaperTileDim
								sourceSize.width: Math.round(tile.width * Config.wallpaperTileDouble)
								sourceSize.height: Math.round(tile.height * Config.wallpaperTileDouble)
								source: "file://" + cell.modelData.preview

								Behavior on opacity {
									NumberAnimation {
										duration: Config.wallpaperFadeMs
										easing.type: Easing.OutCubic
									}
								}
							}

							Rectangle {
								anchors.fill: parent
								color: "transparent"
								visible: cell.current
								border.width: Config.wallpaperRingWidth
								border.color: Config.foreground
							}

							Rectangle {
								id: badge

								anchors.right: parent.right
								anchors.bottom: parent.bottom
								visible: cell.applied
								width: Math.max(mark.implicitWidth, mark.implicitHeight) + 8
								height: Math.max(mark.implicitWidth, mark.implicitHeight) + 8
								color: Config.surface

								Text {
									id: mark

									anchors.centerIn: parent
									font.family: Config.fontFamily
									font.pixelSize: Config.wallpaperMarkSize
									color: Config.foreground
									text: Config.launcherIconActive
								}
							}

							HoverHandler {
								onPointChanged: {
									if (!hovered)
										return;

									const next = Util.pointerMoved(root.pointer, point.scenePosition, root.tileHeight);

									root.pointer = next;

									if (next.moved)
										root.currentIndex = cell.index;
								}
							}

							MouseArea {
								anchors.fill: parent

								onClicked: {
									root.currentIndex = cell.index;
									root.applyCurrent();
								}
							}
						}
					}
				}

				MouseArea {
					anchors.fill: grid
					acceptedButtons: Qt.NoButton

					onWheel: function (wheel) {
						grid.contentY = Util.clamp(grid.contentY - wheel.angleDelta.y, 0, Math.max(0, grid.contentHeight - grid.height));
						wheel.accepted = true;
					}
				}

				Scrollbar {
					view: grid
					offset: Config.wallpaperTileGap
				}
			}
		}
	}
}
