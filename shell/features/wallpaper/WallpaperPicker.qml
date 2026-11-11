import QtQuick
import Quickshell
import Quickshell.Wayland
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
	readonly property string themeListing: JSON.stringify(Yudae.themes)
	readonly property var themes: JSON.parse(root.themeListing)
	property var wallpapers: []
	property int currentIndex: 0
	property int settledIndex: -1
	property int themeIndex: 0
	property int row: 0

	readonly property var held: root.currentIndex >= 0 && root.currentIndex < root.wallpapers.length ? root.wallpapers[root.currentIndex] : null
	readonly property real tileHeight: Config.wallpaperRowHeight
	readonly property real wideWidth: Math.round(root.tileHeight * Config.wallpaperPreviewRatio)
	readonly property real slimWidth: Math.round(root.tileHeight * Config.wallpaperSlimRatio)
	readonly property bool themed: root.themes.length > 0
	readonly property real contentHeight: root.tileHeight + (root.themed ? Config.wallpaperSectionGap + Config.themeCardHeight : 0)
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

	onListingChanged: {
		root.wallpapers = root.state.list || [];
		root.selectActive();
	}

	onCurrentIndexChanged: settle.restart()

	Timer {
		id: settle

		interval: 140
		onTriggered: root.settledIndex = root.currentIndex
	}

	function selectActive() {
		const index = root.wallpapers.map(function (entry) { return entry.path; }).indexOf(root.activeWallpaper);

		root.currentIndex = index >= 0 ? index : 0;
		root.settledIndex = root.currentIndex;
	}

	function move(step) {
		if (root.row === 1)
			root.themeIndex = Calc.clamp(root.themeIndex + step, 0, root.themes.length - 1);
		else if (root.wallpapers.length > 0)
			root.currentIndex = Calc.clamp(root.currentIndex + step, 0, root.wallpapers.length - 1);
	}

	function setRow(next) {
		root.row = next === 1 && root.themed ? 1 : 0;
	}

	function open() {
		root.shown = true;
		root.row = 0;
		root.selectActive();
		root.themeIndex = Math.max(0, root.themes.findIndex(function (entry) { return entry.active; }));

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
		if (root.active)
			Yudae.cmd("wallpaper", { scan: true });
	}

	function applyCurrent() {
		if (root.row === 1) {
			Yudae.setTheme(root.themes[root.themeIndex].id);
			return;
		}

		if (root.held === null)
			return;

		Yudae.cmd("wallpaper", { apply: { path: root.held.path, band: BarInk.bandPx() } });
		root.close();
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

		Column {
			id: layout

			width: parent.width
			spacing: Config.wallpaperSectionGap

			ListView {
				id: strip

				width: parent.width
				height: root.tileHeight
				orientation: ListView.Horizontal
				clip: true
				interactive: false
				keyNavigationEnabled: false
				spacing: Config.wallpaperTileGap
				model: root.wallpapers
				currentIndex: root.currentIndex
				highlightRangeMode: ListView.StrictlyEnforceRange
				preferredHighlightBegin: (strip.width - root.wideWidth) / 2
				preferredHighlightEnd: (strip.width + root.wideWidth) / 2
				highlightMoveDuration: Config.wallpaperFadeMs
				cacheBuffer: root.wideWidth

				delegate: Item {
					id: cell

					required property var modelData
					required property int index

					readonly property bool current: cell.index === root.currentIndex
					readonly property bool applied: cell.modelData.path === root.activeWallpaper

					width: cell.current ? root.wideWidth : root.slimWidth
					height: strip.height
					clip: true

					Behavior on width {
						NumberAnimation {
							duration: Config.wallpaperFadeMs
							easing.type: Easing.OutCubic
						}
					}

					Rectangle {
						anchors.fill: parent
						color: Config.launcherSearchBox
					}

					Item {
						anchors.centerIn: parent
						width: root.wideWidth
						height: parent.height
						opacity: cell.current ? 1 : Config.wallpaperTileDim

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
							visible: cell.current
							opacity: status === Image.Ready ? 1 : 0
							source: cell.index === root.settledIndex ? "file://" + (cell.modelData.preview || cell.modelData.path) : ""

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
						visible: cell.current && root.row === 0
						border.width: Config.wallpaperRingWidth
						border.color: Config.foreground
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
							root.row = 0;

							if (cell.current)
								root.applyCurrent();
							else
								root.currentIndex = cell.index;
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
						root.row = 0;
						root.move(wheel.angleDelta.y > 0 ? -1 : 1);
						wheel.accepted = true;
					}
				}
			}

			ListView {
				id: shelf

				anchors.horizontalCenter: parent.horizontalCenter
				width: Math.min(parent.width, shelf.contentWidth)
				height: Config.themeCardHeight
				visible: root.themed
				orientation: ListView.Horizontal
				clip: true
				interactive: false
				keyNavigationEnabled: false
				spacing: Config.wallpaperTileGap
				model: root.themes
				currentIndex: root.themeIndex
				highlightMoveDuration: Config.wallpaperFadeMs
				opacity: root.row === 1 ? 1 : Config.wallpaperTileDim

				Behavior on opacity {
					NumberAnimation {
						duration: Config.wallpaperFadeMs
						easing.type: Easing.OutCubic
					}
				}

				delegate: Rectangle {
					id: chip

					required property var modelData
					required property int index

					width: Config.themeCardWidth
					height: shelf.height
					color: chip.modelData.surface || Config.surface

					Text {
						x: Config.themeCardPadding
						y: Config.themeCardPadding
						width: parent.width - Config.themeCardPadding * 2
						elide: Text.ElideRight
						font.family: Config.fontFamily
						font.pixelSize: Config.wallpaperNameSize
						color: chip.modelData.foreground || Config.foreground
						text: chip.modelData.id
					}

					Row {
						x: Config.themeCardPadding
						anchors.bottom: parent.bottom
						anchors.bottomMargin: Config.themeCardPadding
						spacing: Config.themeSwatchGap

						Repeater {
							model: chip.modelData.accents

							Rectangle {
								required property string modelData

								width: Config.themeSwatchSize
								height: Config.themeSwatchSize
								color: modelData
							}
						}
					}

					Rectangle {
						anchors.fill: parent
						color: "transparent"
						visible: root.row === 1 && chip.index === root.themeIndex
						border.width: Config.wallpaperRingWidth
						border.color: chip.modelData.foreground || Config.foreground
					}

					Rectangle {
						anchors.right: parent.right
						anchors.bottom: parent.bottom
						visible: chip.modelData.active
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
							root.row = 1;
							root.themeIndex = chip.index;
							root.applyCurrent();
						}
					}
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
		}
	}
}
