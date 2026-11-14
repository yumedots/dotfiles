import QtQuick
import qs

Item {
	id: root

	property bool open: false
	property color color: Config.launcherSearchBox
	property real padding: Config.rowInset
	property real bleed: Config.rowInset
	property real spacing: Config.networkRowGap
	property real maxHeight: 0

	default property alias content: body.data

	readonly property real natural: body.implicitHeight + 2 * root.padding

	visible: root.height > 0
	height: root.open ? (root.maxHeight > 0 ? Math.min(root.natural, root.maxHeight) : root.natural) : 0

	Behavior on height {
		NumberAnimation {
			duration: Config.toggleMs
			easing.type: Easing.OutCubic
		}
	}

	Rectangle {
		x: -root.bleed
		width: root.width + 2 * root.bleed
		height: root.height
		radius: Math.min(height / 2, Config.rowRadius + root.bleed)
		color: root.color
	}

	Flickable {
		id: view

		y: root.padding
		width: root.width
		height: root.height - 2 * root.padding
		contentWidth: width
		contentHeight: body.implicitHeight
		clip: true
		boundsBehavior: Flickable.StopAtBounds
		flickDeceleration: 100000
		interactive: view.contentHeight > view.height + 1

		Column {
			id: body

			width: view.width
			spacing: root.spacing
		}
	}
}
