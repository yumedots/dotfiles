import QtQuick
import qs

Item {
	id: root

	property bool open: false
	property color color: Config.launcherSearchBox
	property real padding: Config.rowInset
	property real spacing: Config.networkRowGap
	property real maxHeight: 0

	default property alias content: body.data

	readonly property real natural: body.implicitHeight + 2 * root.padding

	clip: true
	visible: root.height > 0
	height: root.open ? (root.maxHeight > 0 ? Math.min(root.natural, root.maxHeight) : root.natural) : 0

	Behavior on height {
		NumberAnimation {
			duration: Config.toggleMs
			easing.type: Easing.OutCubic
		}
	}

	Rectangle {
		anchors.fill: parent
		radius: Math.min(height / 2, Config.rowHeight / 2 + root.padding)
		color: root.color
	}

	MouseArea {
		anchors.fill: parent
		acceptedButtons: Qt.NoButton
	}

	Flickable {
		id: view

		x: root.padding
		y: root.padding
		width: root.width - 2 * root.padding
		height: root.height - 2 * root.padding
		contentWidth: width
		contentHeight: body.implicitHeight
		clip: true
		boundsBehavior: Flickable.StopAtBounds
		interactive: view.contentHeight > view.height + 1

		Column {
			id: body

			width: view.width
			spacing: root.spacing
		}
	}

	Scrollbar {
		view: view
	}
}
