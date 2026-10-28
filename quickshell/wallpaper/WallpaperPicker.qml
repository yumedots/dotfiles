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
	property var wallpapers: []
	property int currentIndex: 0
	property var pointer: null

	readonly property var held: root.currentIndex >= 0 && root.currentIndex < root.wallpapers.length ? root.wallpapers[root.currentIndex] : null
	readonly property string shotPath: root.held === null ? "" : root.held.path
	readonly property int columns: Math.max(1, Config.wallpaperColumns)
	readonly property real heroWidth: Config.wallpaperStageWidth
	readonly property real heroHeight: Math.round(root.heroWidth / Config.wallpaperPreviewRatio)
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

	onListingChanged: {
		root.wallpapers = root.state.list || [];
		root.selectActive();
	}

	property string heroPath: ""
	property string heroThumb: ""
	property string heroPreview: ""

	onCurrentIndexChanged: {
		root.reveal();

		if (root.shown || card.opacity > 0)
			heroTimer.restart();
	}

	onShownChanged: {
		if (!root.shown)
			return;

		root.setHero();
	}

	Timer {
		id: heroTimer

		interval: 140
		onTriggered: root.setHero()
	}

	function setHero() {
		const entry = root.held;
		root.heroPath = entry === null ? "" : entry.path;
		root.heroThumb = entry !== null && entry.thumb ? entry.thumb : root.heroPath;
		root.heroPreview = entry !== null && entry.preview ? entry.preview : root.heroPath;
	}

	function reveal() {
		if (root.currentIndex >= 0 && grid.count > 0)
			grid.positionViewAtIndex(root.currentIndex, GridView.Contain);
	}

	function selectActive() {
		const active = root.state.active || "";
		const index = root.wallpapers.map(function (entry) { return entry.path; }).indexOf(active);

		root.currentIndex = index >= 0 ? index : 0;
		Qt.callLater(root.reveal);
	}

	function move(step) {
		if (root.wallpapers.length === 0)
			return;

		root.currentIndex = Calc.clamp(root.currentIndex + step, 0, root.wallpapers.length - 1);
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
		if (root.active)
			Yudae.wallpaperScan();
	}

	function applyCurrent() {
		if (root.held === null)
			return;

		Yudae.wallpaperApply(root.held.path, BarInk.bandPx());
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
						id: heroQuick

						anchors.fill: parent
						fillMode: Image.PreserveAspectCrop
						cache: true
						asynchronous: true
						retainWhileLoading: true
						source: root.heroThumb === "" ? "" : "file://" + root.heroThumb
					}

					Image {
						id: heroShot

						anchors.fill: parent
						fillMode: Image.PreserveAspectCrop
						cache: true
						asynchronous: true
						retainWhileLoading: true
						opacity: status === Image.Ready ? 1 : 0
						source: root.heroPreview === "" ? "" : "file://" + root.heroPreview

						Behavior on opacity {
							NumberAnimation {
								duration: Config.wallpaperFadeMs
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
								source: "file://" + (cell.modelData.thumb || cell.modelData.path)

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

									const at = point.scenePosition;
									const prev = root.pointer;

									if (!prev) {
										root.pointer = { x: at.x, y: at.y, engaged: false };
										return;
									}

									if (prev.engaged || (at.x - prev.x) ** 2 + (at.y - prev.y) ** 2 >= root.tileHeight ** 2) {
										root.pointer = { x: at.x, y: at.y, engaged: true };

										if (at.x !== prev.x || at.y !== prev.y)
											root.currentIndex = cell.index;
									}
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
						grid.contentY = Calc.clamp(grid.contentY - wheel.angleDelta.y, 0, Math.max(0, grid.contentHeight - grid.height));
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
