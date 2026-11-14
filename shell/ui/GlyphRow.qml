import QtQuick
import qs
import qs.services

Item {
	id: row

	property string glyph: ""
	property string label: ""
	property bool current: false
	property bool selected: false
	property bool dim: false
	property bool hoverable: false
	property real glyphSize: Settings.fontSize + 2

	default property alias trailing: tail.data

	readonly property bool hot: row.selected || (row.hoverable && hit.containsMouse)
	readonly property real badge: Config.rowHeight - 2 * Config.rowInset
	readonly property color ink: row.dim && !row.hot ? Config.muted : hl.ink

	signal activated()

	implicitHeight: Config.rowHeight
	height: row.implicitHeight

	Highlight {
		id: hl

		active: row.hot
	}

	MouseArea {
		id: hit

		anchors.fill: parent
		hoverEnabled: row.hoverable

		onClicked: row.activated()
	}

	Item {
		id: iconSlot

		anchors.left: parent.left
		anchors.leftMargin: Config.rowInset
		anchors.verticalCenter: parent.verticalCenter
		width: row.badge
		height: row.badge

		Rectangle {
			anchors.fill: parent
			radius: width / 2
			color: Config.foreground
			visible: row.current
		}

		Glyph {
			anchors.fill: parent
			size: row.glyphSize
			color: row.current ? Config.surface : row.ink
			glyph: row.glyph
		}
	}

	Row {
		id: tail

		anchors.right: parent.right
		anchors.rightMargin: Config.rowInset
		anchors.verticalCenter: parent.verticalCenter
		spacing: Config.mixerListGap
	}

	Text {
		anchors.left: iconSlot.right
		anchors.leftMargin: Config.mixerListGap
		anchors.right: tail.left
		anchors.rightMargin: tail.children.length > 0 ? Config.mixerListGap : 0
		anchors.verticalCenter: parent.verticalCenter
		elide: Text.ElideRight
		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		color: row.ink
		text: row.label
	}
}
