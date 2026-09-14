import QtQuick
import qs

Item {
	id: root

	property var settings: null

	readonly property real baselineLift: 0

	implicitWidth: root.settings && root.settings.size ? root.settings.size : Config.spacing
	implicitHeight: 1
}
