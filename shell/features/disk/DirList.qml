pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.ui

Item {
	id: root

	property var items: []
	property var selected: ({})
	readonly property real maxSize: root.items.length > 0 ? Math.max(1, Number(root.items[0].size) || 1) : 1

	signal activated(var item)
	signal toggled(var item)

	ListView {
		id: list

		anchors.fill: parent
		clip: true
		model: root.items
		spacing: 6
		boundsBehavior: Flickable.StopAtBounds

		delegate: Item {
			id: row

			required property var modelData

			readonly property bool checked: root.selected[row.modelData.path] !== undefined
			readonly property bool isDir: row.modelData.kind === "dir"
			readonly property real share: (Number(row.modelData.size) || 0) / root.maxSize
			readonly property color tint: row.isDir ? Config.diskDir : Config.diskFile

			width: list.width - 14
			height: 58

			Rectangle {
				anchors.fill: parent
				radius: 8
				color: row.checked ? Config.diskAccent : (rowMouse.containsMouse ? Config.launcherHighlight : Config.launcherSearchBox)
				opacity: row.checked ? 0.16 : 0.7
				border.color: row.checked ? Config.diskAccent : "transparent"
				border.width: 1
			}

			MouseArea {
				id: rowMouse

				anchors.fill: parent
				hoverEnabled: true
				onClicked: if (row.isDir) root.activated(row.modelData)
			}

			Check {
				id: box

				anchors.left: parent.left
				anchors.leftMargin: 14
				anchors.verticalCenter: parent.verticalCenter
				checked: row.checked
				onToggled: root.toggled(row.modelData)
			}

			Rectangle {
				id: tile

				anchors.left: box.right
				anchors.leftMargin: 14
				anchors.verticalCenter: parent.verticalCenter
				width: 38
				height: 38
				radius: 10
				color: row.tint

				Glyph {
					anchors.centerIn: parent
					glyph: row.isDir ? Config.diskIconDir : Config.diskIconFile
					size: 18
					color: Config.foreground
				}
			}

			Column {
				anchors.left: tile.right
				anchors.leftMargin: 14
				anchors.right: bar.left
				anchors.rightMargin: 18
				anchors.verticalCenter: parent.verticalCenter
				spacing: 3

				Text {
					width: parent.width
					elide: Text.ElideMiddle

					font.family: Config.fontFamily
					font.pixelSize: 14
					font.weight: Font.Medium
					color: Config.foreground
					text: row.modelData.name
				}

				Text {
					width: parent.width
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: 11
					color: Config.dim
					text: row.isDir ? ((row.modelData.children || 0) + " items") : "File"
				}
			}

			Rectangle {
				id: bar

				anchors.right: sizeLabel.left
				anchors.rightMargin: 20
				anchors.verticalCenter: parent.verticalCenter
				width: Math.max(120, row.width * 0.26)
				height: 8
				radius: 4
				color: Config.launcherHighlight

				Rectangle {
					width: Math.max(8, parent.width * row.share)
					height: parent.height
					radius: 4
					color: row.tint
				}
			}

			Text {
				id: sizeLabel

				anchors.right: parent.right
				anchors.rightMargin: 16
				anchors.verticalCenter: parent.verticalCenter
				width: 78
				horizontalAlignment: Text.AlignRight

				font.family: Config.fontFamily
				font.pixelSize: 13
				font.weight: Font.Medium
				color: Config.foreground
				text: row.modelData.sizeText || ""
			}
		}
	}

	Scrollbar {
		view: list
	}
}
