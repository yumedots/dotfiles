import QtQuick
import qs
import qs.ui

Item {
	id: root

	property var rows: []
	property real total: 0
	property bool canClean: false

	signal clean()

	Rectangle {
		anchors.fill: parent
		color: Config.diskSidebar
	}

	Rectangle {
		anchors.right: parent.right
		anchors.top: parent.top
		anchors.bottom: parent.bottom
		width: 1
		color: Config.foreground
		opacity: 0.18
	}

	Text {
		id: title

		anchors.left: parent.left
		anchors.leftMargin: 14
		anchors.top: parent.top
		anchors.topMargin: 14

		font.family: Config.fontFamily
		font.pixelSize: 12
		font.weight: Font.DemiBold
		color: Config.foreground
		text: "Selected"
	}

	Text {
		anchors.right: parent.right
		anchors.rightMargin: 14
		anchors.verticalCenter: title.verticalCenter

		font.family: Config.fontFamily
		font.pixelSize: 10
		color: Config.dim
		text: root.rows.length + " items"
	}

	ListView {
		id: list

		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: title.bottom
		anchors.topMargin: 10
		anchors.bottom: footer.top
		anchors.leftMargin: 6
		anchors.rightMargin: 6
		clip: true
		model: root.rows
		spacing: 1

		delegate: Item {
			id: row

			required property var modelData

			width: list.width
			height: 28

			Text {
				anchors.left: parent.left
				anchors.leftMargin: 8
				anchors.right: rowSize.left
				anchors.rightMargin: 8
				anchors.verticalCenter: parent.verticalCenter
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: 11
				color: Config.foreground
				text: row.modelData.name || row.modelData.label || ""
			}

			Text {
				id: rowSize

				anchors.right: parent.right
				anchors.rightMargin: 8
				anchors.verticalCenter: parent.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: 10
				color: Config.dim
				text: row.modelData.sizeText || ""
			}
		}
	}

	Scrollbar {
		view: list
	}

	Item {
		id: footer

		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		height: 70

		Rectangle {
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.top: parent.top
			height: 1
			color: Config.dim
		}

		Text {
			anchors.left: parent.left
			anchors.leftMargin: 14
			anchors.top: parent.top
			anchors.topMargin: 10

			font.family: Config.fontFamily
			font.pixelSize: 11
			color: Config.dim
			text: "Total"
		}

		Text {
			anchors.right: parent.right
			anchors.rightMargin: 14
			anchors.top: parent.top
			anchors.topMargin: 10

			font.family: Config.fontFamily
			font.pixelSize: 11
			color: Config.foreground
			text: root.total > 0 ? root.formatSize(root.total) : ""
		}

		Rectangle {
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.bottom: parent.bottom
			anchors.leftMargin: 12
			anchors.rightMargin: 12
			anchors.bottomMargin: 10
			height: 28
			color: root.canClean && cleanMouse.containsMouse ? Config.launcherHighlight : Config.launcherSearchBox
			opacity: root.canClean ? 1 : 0.45

			Text {
				anchors.centerIn: parent

				font.family: Config.fontFamily
				font.pixelSize: 12
				color: Config.foreground
				text: "Clean"
			}

			MouseArea {
				id: cleanMouse

				anchors.fill: parent
				hoverEnabled: true
				enabled: root.canClean
				onClicked: root.clean()
			}
		}
	}

	function formatSize(bytes) {
		const value = Number(bytes) || 0;

		if (value >= 1024 * 1024 * 1024 * 1024)
			return (value / (1024 * 1024 * 1024 * 1024)).toFixed(1) + " TB";
		if (value >= 1024 * 1024 * 1024)
			return (value / (1024 * 1024 * 1024)).toFixed(1) + " GB";
		if (value >= 1024 * 1024)
			return (value / (1024 * 1024)).toFixed(1) + " MB";
		if (value >= 1024)
			return (value / 1024).toFixed(1) + " kB";
		return value + " B";
	}
}
