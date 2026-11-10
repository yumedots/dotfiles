import QtQuick
import qs

Rectangle {
	id: root

	property Item anchor: null
	property var entries: []
	property int itemHeight: 32
	property int menuWidth: 190

	signal picked(var entry)

	width: root.menuWidth
	height: column.height + 12
	color: Config.surface
	border.width: 1
	border.color: Config.dim
	visible: false

	function place() {
		if (!root.anchor || !root.parent)
			return;

		const point = root.anchor.mapToItem(root.parent, 0, 0);
		root.x = Math.max(0, Math.min(root.parent.width - root.width, point.x + root.anchor.width - root.width));
		const below = point.y + root.anchor.height + 6;
		root.y = below + root.height <= root.parent.height ? below : Math.max(0, point.y - root.height - 6);
	}

	onVisibleChanged: if (visible) root.place()
	onAnchorChanged: if (visible) root.place()
	onHeightChanged: if (visible) root.place()

	Column {
		id: column

		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: parent.top
		anchors.topMargin: 6

		Repeater {
			model: root.entries

			delegate: Item {
				required property var modelData

				width: column.width
				height: root.itemHeight
				opacity: modelData.enabled === false ? 0.4 : 1

				Rectangle {
					anchors.fill: parent
					color: rowMouse.containsMouse && rowMouse.enabled ? Config.launcherHighlight : "transparent"
				}

				Text {
					anchors.left: parent.left
					anchors.leftMargin: 12
					anchors.verticalCenter: parent.verticalCenter

					font.family: Config.fontFamily
					font.pixelSize: 12
					color: modelData.danger === true ? Config.red : Config.foreground
					text: modelData.label
				}

				MouseArea {
					id: rowMouse

					anchors.fill: parent
					hoverEnabled: true
					enabled: modelData.enabled !== false
					onClicked: root.picked(modelData)
				}
			}
		}
	}
}
