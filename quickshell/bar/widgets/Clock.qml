import QtQuick
import Quickshell
import qs.ui
import qs
import "../../tooltips"

BarText {
	id: root

	property var settings: null

	readonly property string stamp: Qt.formatDateTime(clock.date, root.settings && root.settings.format ? root.settings.format : Config.clockFormat)

	text: root.stamp

	SystemClock {
		id: clock
		precision: SystemClock.Seconds
	}

	popupContent: Calendar {
		onCloseRequested: root.closePopup()
	}
}
