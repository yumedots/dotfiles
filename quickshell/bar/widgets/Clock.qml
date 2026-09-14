import QtQuick
import Quickshell
import qs.ui
import qs

BarText {
	id: root

	property var settings: null

	text: Qt.formatDateTime(clock.date, root.settings && root.settings.format ? root.settings.format : Config.clockFormat)

	SystemClock {
		id: clock
		precision: SystemClock.Seconds
	}
}
