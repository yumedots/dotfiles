import QtQuick
import qs

Rectangle {
	id: root

	property Item anchor: null
	property string title: "Settings"
	property var rows: []

	signal changed(int index, int value)

	width: 250
	height: column.height + 16
	color: Config.surface
	border.width: 1
	border.color: "#1f1f1f"
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
		anchors.topMargin: 8
		spacing: 2

		Text {
			width: parent.width - 24
			x: 12
			height: 22
			verticalAlignment: Text.AlignVCenter

			font.family: Config.fontFamily
			font.pixelSize: 12
			color: Config.muted
			text: root.title
		}

		Repeater {
			model: root.rows

			delegate: Item {
				required property var modelData
				required property int index

				width: column.width
				height: 34

				Text {
					anchors.left: parent.left
					anchors.leftMargin: 12
					anchors.verticalCenter: parent.verticalCenter

					font.family: Config.fontFamily
					font.pixelSize: 12
					color: Config.foreground
					text: modelData.label
				}

				Row {
					anchors.right: parent.right
					anchors.rightMargin: 10
					anchors.verticalCenter: parent.verticalCenter
					spacing: 2

					Item {
						width: 20
						height: 24

						Text {
							anchors.centerIn: parent
							font.family: Config.fontFamily
							font.pixelSize: 12
							color: minusMouse.containsMouse ? Config.foreground : Config.dim
							text: "\uf068"
						}

						MouseArea {
							id: minusMouse

							anchors.fill: parent
							hoverEnabled: true
							onClicked: root.changed(index, Math.max(modelData.min, modelData.value - modelData.step))
						}
					}

					Text {
						width: 64
						height: 24
						horizontalAlignment: Text.AlignHCenter
						verticalAlignment: Text.AlignVCenter

						font.family: Config.fontFamily
						font.pixelSize: 12
						color: Config.foreground
						text: modelData.value + (modelData.suffix ? " " + modelData.suffix : "")
					}

					Item {
						width: 20
						height: 24

						Text {
							anchors.centerIn: parent
							font.family: Config.fontFamily
							font.pixelSize: 12
							color: plusMouse.containsMouse ? Config.foreground : Config.dim
							text: "\uf067"
						}

						MouseArea {
							id: plusMouse

							anchors.fill: parent
							hoverEnabled: true
							onClicked: root.changed(index, Math.min(modelData.max, modelData.value + modelData.step))
						}
					}
				}
			}
		}
	}
}
