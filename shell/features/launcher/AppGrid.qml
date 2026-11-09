import QtQuick
import qs
import qs.ui
import qs.services

Item {
	id: grid

	required property var results
	required property int currentIndex

	signal hovered(int index, point at)
	signal clicked(int index)

	readonly property int columns: Config.launcherGridColumns
	readonly property int rows: Config.launcherGridRows

	implicitWidth: grid.columns * Config.launcherGridCell
	implicitHeight: grid.rows * Config.launcherGridCellHeight

	function reset() {
		view.contentY = 0;
	}

	GridView {
		id: view

		anchors.fill: parent
		clip: true
		cellWidth: Config.launcherGridCell
		cellHeight: Config.launcherGridCellHeight
		model: grid.results
		currentIndex: grid.currentIndex
		boundsBehavior: Flickable.StopAtBounds
		keyNavigationEnabled: false
		highlightFollowsCurrentItem: true
		highlightMoveDuration: 0
		highlight: Highlight {
			fillParent: false
		}

		onCurrentIndexChanged: view.positionViewAtIndex(view.currentIndex, GridView.Contain)

		delegate: Item {
			id: tile

			required property var modelData
			required property int index

			readonly property bool active: tile.index === view.currentIndex
			readonly property string icon: tile.modelData.appId ? AppIcons.iconOf(tile.modelData.appId) : ""
			readonly property string glyph: tile.modelData.glyph || (tile.modelData.appId ? AppIcons.glyphOf(tile.modelData.appId) : "")
			readonly property bool hasIcon: tile.icon !== "" && image.status !== Image.Error

			width: view.cellWidth
			height: view.cellHeight

			Item {
				id: face

				anchors.horizontalCenter: parent.horizontalCenter
				y: Config.launcherGap * 2
				width: Config.launcherGridIconSize
				height: Config.launcherGridIconSize

				Text {
					anchors.centerIn: parent
					visible: !tile.hasIcon
					font.family: Config.fontFamily
					font.pixelSize: Math.round(Config.launcherGridIconSize * 0.75)
					color: Config.foreground
					text: tile.glyph
				}

				AppIcon {
					id: image

					anchors.centerIn: parent
					implicitSize: Config.launcherGridIconSize
					visible: tile.icon !== ""
					source: tile.icon
				}

				Text {
					anchors.right: parent.right
					anchors.top: parent.top
					visible: tile.modelData.pinned === true
					font.family: Config.fontFamily
					font.pixelSize: Config.launcherGridLabelSize
					color: Config.foreground
					text: Config.launcherIconPin
				}
			}

			Text {
				id: label

				anchors.top: face.bottom
				anchors.topMargin: Config.launcherGap
				anchors.horizontalCenter: parent.horizontalCenter
				width: tile.width - Config.launcherTextGap
				horizontalAlignment: Text.AlignHCenter
				wrapMode: Text.Wrap
				maximumLineCount: 2
				elide: Text.ElideRight
				font.family: Config.fontFamily
				font.pixelSize: Config.launcherGridLabelSize
				color: tile.active ? Config.launcherHighlightText : Config.foreground
				text: tile.modelData.name
			}

			HoverHandler {
				onPointChanged: {
					if (hovered)
						grid.hovered(tile.index, point.scenePosition);
				}
			}

			MouseArea {
				anchors.fill: parent

				onClicked: grid.clicked(tile.index)
			}
		}
	}
}
