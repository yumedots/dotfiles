import QtQuick
import qs

Text {
	id: root

	signal clicked()

	property bool shown: true
	property real hitMargin: -4
	property int fadeMs: Config.popupFadeMs
	property color baseColor: Config.muted
	property color hoverColor: Config.foreground

	opacity: root.shown ? 1 : 0
	font.family: Config.fontFamily
	color: hit.containsMouse ? root.hoverColor : root.baseColor

	Behavior on opacity {
		NumberAnimation {
			duration: root.fadeMs
		}
	}

	MouseArea {
		id: hit

		anchors.fill: parent
		anchors.margins: root.hitMargin
		hoverEnabled: true
		enabled: root.shown
		onClicked: root.clicked()
	}
}
