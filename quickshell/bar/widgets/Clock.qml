import QtQuick
import Quickshell
import qs.ui
import qs
import "../../tooltips"

BarText {
	id: root

	property var settings: null
	property var bar: null

	readonly property string stamp: Qt.formatDateTime(clock.date, root.settings && root.settings.format ? root.settings.format : Config.clockFormat)

	text: Config.iconClock + "  " + root.stamp

	function openPopup() {
		popup.open();
	}

	function closePopup() {
		popup.hideNow();
	}

	function isPopupOpen() {
		return popup.shown;
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
			onCloseRequested: popup.close()
		}
	}
}
