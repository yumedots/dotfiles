import QtQuick
import Quickshell
import qs
import qs.ui

// One row of agent work: the figure that says what the session is doing, the
// mark of the provider that is doing it, and its title.
//
// The figure comes first, so the state of the work is read before anything
// else, and the mark of the provider after it.
Item {
	id: root

	// working | question | failed | done
	property string kind: ""

	// The mark of the provider that is doing the work.
	property string icon: ""

	property string title: ""

	property real rowHeight: Settings.fontSize + 6

	// Whether the row can be taken off the list.
	property bool dismissable: false

	signal dismissed()

	// The marks are drawn at the size of the screen, so a small svg stays
	// sharp instead of being scaled up from a small raster.
	readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1

	implicitHeight: root.rowHeight

	// The figure that says what the session is doing: a braille spinner
	// while it works, a question mark when it asks something, a cross when
	// it failed, and a check when the work is over.
	Braille {
		id: spinner

		x: 0
		y: 1
		width: 12
		height: root.rowHeight - 2

		visible: root.kind === "working"
		running: root.kind === "working"
		ink: Config.foreground
	}

	Text {
		x: 0
		y: 0
		width: 12
		height: root.rowHeight

		visible: root.kind !== "working"
		verticalAlignment: Text.AlignVCenter
		horizontalAlignment: Text.AlignHCenter

		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		color: root.kind === "done" ? Config.muted : Config.red
		text: root.kind === "question"
			? Config.agentIconQuestion
			: (root.kind === "failed" ? Config.agentIconClose : Config.agentIconDone)
	}

	// The mark of the provider that is doing the work.
	Image {
		id: mark

		x: 16
		y: 1
		width: 15
		height: 15

		visible: root.icon !== ""

		source: root.icon !== ""
			? "file://" + Quickshell.shellDir + "/assets/providers/" + root.icon + ".svg?v=3"
			: ""
		sourceSize.width: Math.round(15 * root.dpr)
		sourceSize.height: Math.round(15 * root.dpr)
		fillMode: Image.PreserveAspectFit
	}

	Text {
		anchors.left: mark.visible ? mark.right : spinner.right
		anchors.leftMargin: mark.visible ? 6 : 8
		anchors.right: dismiss.visible ? dismiss.left : parent.right
		anchors.rightMargin: dismiss.visible ? 6 : 0
		anchors.verticalCenter: parent.verticalCenter

		elide: Text.ElideRight

		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		color: root.kind === "done" ? Config.muted : (root.kind === "working" ? Config.foreground : Config.red)
		text: root.title
	}

	// The cross that takes the finished work off the list.
	Text {
		id: dismiss

		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		width: 14

		visible: root.dismissable
		horizontalAlignment: Text.AlignHCenter

		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		color: dismissHit.containsMouse ? Config.foreground : Config.muted
		text: Config.iconClose

		MouseArea {
			id: dismissHit

			anchors.fill: parent
			anchors.margins: -4

			onClicked: root.dismissed()
		}
	}
}
