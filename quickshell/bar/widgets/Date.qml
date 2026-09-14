import QtQuick
import Quickshell
import qs.ui
import qs
import "../../tooltips"

BarText {
	id: root

	property var bar: null

	text: Qt.formatDateTime(clock.date, Config.dateFormat)

	function togglePopup() {
		popup.toggle();
	}

	function closePopup() {
		popup.hideNow();
	}

	SystemClock {
		id: clock
		precision: SystemClock.Seconds
	}

	MouseArea {
		id: area		anchors.fill: parent

		onClicked: root.bar ? root.bar.openExclusive(root) : popup.toggle()

	}

	Tooltip {
		id: popup

		anchorWindow: root.bar
		anchorItem: root

		Calendar {
			today: clock.date
		}
	}
}
