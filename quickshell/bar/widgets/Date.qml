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

	Tooltip {
		id: popup

		anchorWindow: root.bar
		anchorItem: root
		wantsKeyboard: true

		Calendar {
			today: clock.date

			onCloseRequested: popup.close()
		}
	}
}
