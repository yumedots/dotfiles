import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.ui

PanelWindow {
	id: root

	property bool shown: false
	property bool active: true
	property bool alwaysMapped: false

	readonly property var state: Yudae.wallpaper
	readonly property string listing: (root.state.list || []).map(function (entry) { return entry.path; }).join("\n")
	readonly property string activeWallpaper: root.state.active || ""
	readonly property string themeListing: JSON.stringify(Yudae.themes.map(function (entry) { return { id: entry.id, surface: entry.surface, foreground: entry.foreground, accents: entry.accents, cover: entry.cover, background: entry.background }; }))
	readonly property var themes: JSON.parse(root.themeListing)
	readonly property var looks: root.themes.filter(function (entry) { return entry.background !== ""; })
	readonly property string activeTheme: (Yudae.themes.filter(function (entry) { return entry.active; })[0] || ({})).id || "gray"
	property var wallpapers: []
	property int currentIndex: 0
	property int themeIndex: 0
	property int lookIndex: 0
	property int row: 0
	property bool previewing: false
	property int highlightMs: Config.wallpaperFadeMs
	property bool instant: false
	property bool moved: false
	property bool previewed: false
	property string returnWorkspace: ""
	property string originTheme: ""
	property string originWallpaper: ""

	readonly property var held: root.currentIndex >= 0 && root.currentIndex < root.wallpapers.length ? root.wallpapers[root.currentIndex] : null
	readonly property real tileHeight: Config.wallpaperRowHeight
	readonly property real wideWidth: Math.round(root.tileHeight * Config.wallpaperPreviewRatio)
	readonly property real slimWidth: Math.round(root.tileHeight * Config.wallpaperSlimRatio)
	readonly property real rowMin: Config.wallpaperRowMin
	readonly property real contentHeight: stage.implicitHeight
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

	onListingChanged: root.refreshWallpapers()
	onThemesChanged: root.refreshWallpapers()

	function refreshWallpapers() {
		const list = (root.state.list || []).slice();
		const seen = list.map(function (entry) { return entry.path; });

		root.looks.forEach(function (look) {
			if (seen.indexOf(look.background) >= 0)
				return;

			seen.push(look.background);
			list.push({
				path: look.background,
				name: look.id,
				thumb: look.background,
				preview: look.background
			});
		});

		if (root.activeWallpaper !== "" && seen.indexOf(root.activeWallpaper) < 0) {
			list.unshift({
				path: root.activeWallpaper,
				name: root.activeWallpaper.split("/").pop(),
				thumb: root.activeWallpaper,
				preview: root.activeWallpaper
			});
		}

		root.wallpapers = list;

		if (root.shown && !root.moved) {
			root.syncSelection();
			root.positionAll();
			return;
		}

		root.selectActive();
	}

	function selectActive() {
		const index = root.wallpapers.map(function (entry) { return entry.path; }).indexOf(root.activeWallpaper);

		root.highlightMs = 0;
		root.currentIndex = index >= 0 ? index : 0;
		root.positionAll();
	}

	function syncSelection() {
		root.highlightMs = 0;
		root.currentIndex = Math.max(0, root.wallpapers.map(function (entry) { return entry.path; }).indexOf(root.activeWallpaper));
		root.themeIndex = Math.max(0, root.themes.findIndex(function (entry) { return entry.id === root.activeTheme; }));
		root.lookIndex = Math.max(0, root.looks.findIndex(function (entry) { return entry.id === root.activeTheme; }));
	}

	function positionAll() {
		if (looksStrip.count > 0)
			looksStrip.positionViewAtIndex(root.lookIndex, ListView.Center);

		if (strip.count > 0)
			strip.positionViewAtIndex(root.currentIndex, ListView.Center);

		if (themeStrip.count > 0)
			themeStrip.positionViewAtIndex(root.themeIndex, ListView.Center);
	}

	readonly property var rows: {
		const list = [];

		if (root.looks.length > 0)
			list.push(0);
		list.push(1);
		list.push(2);

		return list;
	}

	function move(step) {
		root.moved = true;
		root.highlightMs = Config.wallpaperFadeMs;

		if (root.row === 0)
			root.lookIndex = Calc.clamp(root.lookIndex + step, 0, root.looks.length - 1);
		else if (root.row === 2)
			root.themeIndex = Calc.clamp(root.themeIndex + step, 0, root.themes.length - 1);
		else if (root.wallpapers.length > 0)
			root.currentIndex = Calc.clamp(root.currentIndex + step, 0, root.wallpapers.length - 1);

		moveTimer.restart();
	}

	function stepRow(step) {
		const at = Math.max(0, root.rows.indexOf(root.row));

		root.row = root.rows[(at + step + root.rows.length) % root.rows.length];
		root.positionAll();
	}

	function hideWindows() {
		if (root.previewing)
			return;

		const focused = Hyprland.focusedWorkspace;


		root.returnWorkspace = focused ? focused.name : "";
		root.previewing = true;
		Quickshell.execDetached(["/usr/bin/hyprctl", "dispatch", 'hl.dsp.focus({workspace = 99})']);
	}

	function showWindows() {
		if (!root.previewing)
			return;

		root.previewing = false;

		if (root.returnWorkspace !== "")
			Quickshell.execDetached(["/usr/bin/hyprctl", "dispatch", 'hl.dsp.focus({workspace = "' + root.returnWorkspace + '"})']);
	}

	Timer {
		id: moveTimer

		interval: 140
		onTriggered: root.previewCurrent()
	}

	function previewCurrent() {
		if (!root.shown)
			return;

		if (root.row === 0 && root.looks.length > 0) {
			root.applyLook(root.looks[root.lookIndex]);
			root.previewed = true;
			return;
		}

		if (root.row === 2 && root.themes.length > 0) {
			Yudae.setTheme(root.themes[root.themeIndex].id);
			root.previewed = true;
		}
	}

	function open() {
		root.shown = true;
		root.row = root.rows[0];
		root.selectActive();
		root.themeIndex = Math.max(0, root.themes.findIndex(function (entry) { return entry.id === root.activeTheme; }));
		root.originTheme = root.activeTheme;
		root.originWallpaper = root.activeWallpaper;
		root.previewed = false;
		root.moved = false;
		root.highlightMs = 0;
		root.instant = true;
		root.refreshWallpapers();
		root.syncSelection();
		root.positionAll();
		root.hideWindows();
		Qt.callLater(function () { root.instant = false; });

		if (root.wallpapers.length === 0)
			root.reload();

		Qt.callLater(function () { card.forceActiveFocus(); });
	}

	function close() {
		if (root.previewed) {
			if (root.originTheme !== "")
				Yudae.setTheme(root.originTheme);

			if (root.originWallpaper !== "")
				Yudae.cmd("wallpaper", { apply: { path: root.originWallpaper, band: BarInk.bandPx() } });
		}

		root.previewed = false;
		root.showWindows();
		root.shown = false;
	}

	function toggle() {
		if (root.shown)
			root.close();
		else
			root.open();
	}

	function reload() {
		if (root.active)
			Yudae.cmd("wallpaper", { scan: true });
	}

	function applyCurrent() {
		if (root.row === 1 && root.held !== null)
			Yudae.cmd("wallpaper", { apply: { path: root.held.path, band: BarInk.bandPx() } });
		else
			root.previewCurrent();

		root.previewed = false;
	}

	function applyLook(look) {
		Yudae.setTheme(look.id);

		if (look.background !== "")
			Yudae.cmd("wallpaper", { apply: { path: look.background, band: BarInk.bandPx() } });
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
			enabled: !root.instant

			NumberAnimation {
				duration: Config.wallpaperScrimMs
				easing.type: Easing.OutCubic
			}
		}

		Keys.onPressed: function (event) {
			Input.wallpaper(event, root);
		}

		Column {
			id: stage

			width: parent.width
			spacing: 0

			ListView {
				id: looksStrip

				width: parent.width
				height: root.row === 0 ? root.tileHeight : root.rowMin
				Behavior on height {
					enabled: !root.instant

					NumberAnimation {
						duration: Config.wallpaperFadeMs
						easing.type: Easing.OutCubic
					}
				}


				orientation: ListView.Horizontal
				clip: true
				interactive: false
				keyNavigationEnabled: false
				spacing: 0
				model: root.looks
				currentIndex: root.lookIndex
				highlightRangeMode: ListView.StrictlyEnforceRange
				preferredHighlightBegin: (looksStrip.width - root.wideWidth) / 2
				preferredHighlightEnd: (looksStrip.width + root.wideWidth) / 2
				highlightMoveDuration: root.highlightMs
				cacheBuffer: root.wideWidth

				header: Item {
					width: Math.round((looksStrip.width - root.wideWidth) / 2)
					height: 1
				}

				footer: Item {
					width: Math.round((looksStrip.width - root.wideWidth) / 2)
					height: 1
				}

				delegate: Item {
					id: look

					required property var modelData
					required property int index

					readonly property bool current: look.index === root.lookIndex

					width: look.current ? root.wideWidth : root.slimWidth
					height: looksStrip.height
					clip: true

					Rectangle {
						anchors.fill: parent
						color: look.modelData.surface || Config.surface
					}

					Item {
						anchors.centerIn: parent
						width: root.wideWidth
						height: parent.height
						opacity: 1

						Behavior on opacity {
							NumberAnimation {
								duration: Config.wallpaperFadeMs
								easing.type: Easing.OutCubic
							}
						}

						Image {
							anchors.fill: parent
							fillMode: Image.PreserveAspectCrop
							cache: true
							asynchronous: true
							retainWhileLoading: true
							source: look.modelData.cover === "" ? "" : "file://" + look.modelData.cover
							sourceSize.width: 1024
							sourceSize.height: 1024
							mipmap: true
						}
					}

					Rectangle {
						anchors.fill: parent
						color: "transparent"
					}

					Rectangle {
						anchors.fill: parent
						color: "transparent"
						visible: root.row === 0
						opacity: look.current ? 1 : 0
						border.width: Config.wallpaperRingWidth
						border.color: Config.foreground

						Behavior on opacity {
							NumberAnimation {
								duration: Config.wallpaperFadeMs
							}
						}
					}

					Rectangle {
						anchors.right: parent.right
						anchors.bottom: parent.bottom
						visible: look.modelData.id === (root.previewed ? root.originTheme : root.activeTheme)
						width: Config.wallpaperMarkSize + 8
						height: Config.wallpaperMarkSize + 8
						color: look.modelData.surface || Config.surface

						Glyph {
							anchors.fill: parent
							size: Config.wallpaperMarkSize
							color: look.modelData.foreground || Config.foreground
							glyph: Config.launcherIconActive
						}
					}

					MouseArea {
						anchors.fill: parent

						onClicked: {
							if (root.row !== 0) {
								root.row = 0;
								return;
							}

							root.lookIndex = look.index;
							root.applyCurrent();
						}
					}
				}

				Text {
					anchors.centerIn: parent
					visible: root.looks.length === 0
					font.family: Config.fontFamily
					font.pixelSize: Config.wallpaperNameSize
					color: Config.muted
					text: Config.themeEmpty
				}

				MouseArea {
					anchors.fill: parent
					acceptedButtons: Qt.NoButton

					onWheel: function (wheel) {
						root.row = 0;
						root.move(wheel.angleDelta.y > 0 ? -1 : 1);
						wheel.accepted = true;
					}
				}
			}

			ListView {
				id: strip

				width: parent.width
				height: root.row === 1 ? root.tileHeight : root.rowMin
				Behavior on height {
					enabled: !root.instant

					NumberAnimation {
						duration: Config.wallpaperFadeMs
						easing.type: Easing.OutCubic
					}
				}


				orientation: ListView.Horizontal
				clip: true
				interactive: false
				keyNavigationEnabled: false
				spacing: 0
				model: root.wallpapers
				currentIndex: root.currentIndex
				highlightRangeMode: ListView.StrictlyEnforceRange
				preferredHighlightBegin: (strip.width - root.wideWidth) / 2
				preferredHighlightEnd: (strip.width + root.wideWidth) / 2
				highlightMoveDuration: root.highlightMs
				cacheBuffer: root.wideWidth

				header: Item {
					width: Math.round((strip.width - root.wideWidth) / 2)
					height: 1
				}

				footer: Item {
					width: Math.round((strip.width - root.wideWidth) / 2)
					height: 1
				}

				delegate: Item {
					id: cell

					required property var modelData
					required property int index

					readonly property bool current: cell.index === root.currentIndex
					readonly property bool near: Math.abs(cell.index - root.currentIndex) <= 2
					readonly property bool applied: cell.modelData.path === (root.previewed ? root.originWallpaper : root.activeWallpaper)

					width: cell.current ? root.wideWidth : root.slimWidth
					height: strip.height
					clip: true

					Rectangle {
						anchors.fill: parent
						color: Config.launcherSearchBox
					}

					Item {
						anchors.centerIn: parent
						width: root.wideWidth
						height: parent.height
						opacity: 1

						Behavior on opacity {
							NumberAnimation {
								duration: Config.wallpaperFadeMs
								easing.type: Easing.OutCubic
							}
						}

						Image {
							anchors.fill: parent
							fillMode: Image.PreserveAspectCrop
							cache: true
							asynchronous: true
							retainWhileLoading: true
							source: "file://" + (cell.modelData.thumb || cell.modelData.path)
						}

						Image {
							anchors.fill: parent
							fillMode: Image.PreserveAspectCrop
							cache: true
							asynchronous: true
							visible: cell.near
							opacity: status === Image.Ready ? 1 : 0
							source: cell.near ? "file://" + cell.modelData.path : ""
							sourceSize.width: 1280
							sourceSize.height: 1280
							mipmap: true

							Behavior on opacity {
								NumberAnimation {
									duration: Config.wallpaperFadeMs
								}
							}
						}
					}

					Rectangle {
						anchors.fill: parent
						color: "transparent"
					}

					Rectangle {
						anchors.fill: parent
						color: "transparent"
						visible: root.row === 1
						opacity: cell.current ? 1 : 0
						border.width: Config.wallpaperRingWidth
						border.color: Config.foreground

						Behavior on opacity {
							NumberAnimation {
								duration: Config.wallpaperFadeMs
							}
						}
					}

					Rectangle {
						anchors.right: parent.right
						anchors.bottom: parent.bottom
						visible: cell.applied
						width: Config.wallpaperMarkSize + 8
						height: Config.wallpaperMarkSize + 8
						color: Config.surface

						Glyph {
							anchors.fill: parent
							size: Config.wallpaperMarkSize
							glyph: Config.launcherIconActive
						}
					}

					MouseArea {
						anchors.fill: parent

						onClicked: {
							if (root.row !== 1) {
								root.row = 1;
								return;
							}

							root.currentIndex = cell.index;
							root.applyCurrent();
						}
					}
				}

				Text {
					anchors.centerIn: parent
					visible: root.wallpapers.length === 0
					font.family: Config.fontFamily
					font.pixelSize: Config.wallpaperNameSize
					color: Config.muted
					text: Config.wallpaperEmpty
				}

				MouseArea {
					anchors.fill: parent
					acceptedButtons: Qt.NoButton

					onWheel: function (wheel) {
						root.row = 1;
						root.move(wheel.angleDelta.y > 0 ? -1 : 1);
						wheel.accepted = true;
					}
				}
			}

			ListView {
				id: themeStrip

				width: parent.width
				height: root.row === 2 ? root.tileHeight : root.rowMin
				Behavior on height {
					enabled: !root.instant

					NumberAnimation {
						duration: Config.wallpaperFadeMs
						easing.type: Easing.OutCubic
					}
				}


				orientation: ListView.Horizontal
				clip: true
				interactive: false
				keyNavigationEnabled: false
				spacing: 0
				model: root.themes
				currentIndex: root.themeIndex
				highlightRangeMode: ListView.StrictlyEnforceRange
				preferredHighlightBegin: (themeStrip.width - root.wideWidth) / 2
				preferredHighlightEnd: (themeStrip.width + root.wideWidth) / 2
				highlightMoveDuration: root.highlightMs
				cacheBuffer: root.wideWidth

				header: Item {
					width: Math.round((themeStrip.width - root.wideWidth) / 2)
					height: 1
				}

				footer: Item {
					width: Math.round((themeStrip.width - root.wideWidth) / 2)
					height: 1
				}

				delegate: Item {
					id: chip

					required property var modelData
					required property int index

					readonly property bool current: chip.index === root.themeIndex

					width: chip.current ? root.wideWidth : root.slimWidth
					height: themeStrip.height
					clip: true

					Rectangle {
						anchors.fill: parent
						color: chip.modelData.surface || Config.surface
					}

					Item {
						anchors.centerIn: parent
						width: root.wideWidth
						height: parent.height
						opacity: 1

						Behavior on opacity {
							NumberAnimation {
								duration: Config.wallpaperFadeMs
								easing.type: Easing.OutCubic
							}
						}

						Text {
							anchors.centerIn: parent
							anchors.verticalCenterOffset: -Math.round(parent.height * 0.21)
							font.family: Config.fontFamily
							font.pixelSize: Config.themeNameSize
							color: chip.modelData.foreground || Config.foreground
							text: chip.modelData.id
							opacity: chip.current && root.row === 2 ? 1 : 0

							Behavior on opacity {
								NumberAnimation {
									duration: Config.wallpaperFadeMs
								}
							}
						}

						Row {
							id: themeBand

							anchors.left: parent.left
							anchors.right: parent.right
							anchors.bottom: parent.bottom
							height: Math.round(parent.height * 0.42)

							Repeater {
								model: chip.modelData.accents

								Rectangle {
									required property string modelData

									width: themeBand.width / Math.max(1, chip.modelData.accents.length)
									height: themeBand.height
									color: modelData
								}
							}
						}
					}

					Rectangle {
						anchors.fill: parent
						color: "transparent"
					}

					Rectangle {
						anchors.fill: parent
						color: "transparent"
						visible: root.row === 2
						opacity: chip.current ? 1 : 0
						border.width: Config.wallpaperRingWidth
						border.color: chip.modelData.foreground || Config.foreground

						Behavior on opacity {
							NumberAnimation {
								duration: Config.wallpaperFadeMs
							}
						}
					}

					Rectangle {
						anchors.right: parent.right
						anchors.bottom: parent.bottom
						visible: chip.modelData.id === (root.previewed ? root.originTheme : root.activeTheme)
						width: Config.wallpaperMarkSize + 8
						height: Config.wallpaperMarkSize + 8
						color: chip.modelData.foreground || Config.foreground

						Glyph {
							anchors.fill: parent
							size: Config.wallpaperMarkSize
							color: chip.modelData.surface || Config.surface
							glyph: Config.launcherIconActive
						}
					}

					MouseArea {
						anchors.fill: parent

						onClicked: {
							if (root.row !== 2) {
								root.row = 2;
								return;
							}

							root.themeIndex = chip.index;
							root.applyCurrent();
						}
					}
				}

				Text {
					anchors.centerIn: parent
					visible: root.themes.length === 0
					font.family: Config.fontFamily
					font.pixelSize: Config.wallpaperNameSize
					color: Config.muted
					text: Config.themeEmpty
				}

				MouseArea {
					anchors.fill: parent
					acceptedButtons: Qt.NoButton

					onWheel: function (wheel) {
						root.row = 2;
						root.move(wheel.angleDelta.y > 0 ? -1 : 1);
						wheel.accepted = true;
					}
				}
			}
		}
	}
}
