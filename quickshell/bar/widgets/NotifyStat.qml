import QtQuick
import Quickshell.Services.Notifications
import qs.ui
import qs.services
import qs
import "../../tooltips"

BarStat {
	id: root

	property bool keyboardPopup: false

	icon: Config.iconBell
	value: String(Notifications.count)
	pct: Notifications.empty ? 0 : 100
	barColor: Notifications.empty ? Config.dim : Config.notifyBase
	textColor: Notifications.empty ? Config.dim : Config.foreground
	sweep: true
	sweepWidth: Config.notifySweepWidth

	function wantKeyboard(flag) {
		root.keyboardPopup = flag === true;
	}

	function isPopupOpen() {
		return root.popupVisible && root.keyboardPopup;
	}

	function toast(notification) {
		if (root.isPopupOpen()) {
			toastTimer.stop();
			return;
		}

		if (!root.popupVisible) {
			root.keyboardPopup = false;

			if (root.bar)
				root.bar.openExclusive(root);
			else
				root.openPopup();
		}

		if (notification && notification.urgency === NotificationUrgency.Critical) {
			toastTimer.stop();
			return;
		}

		toastTimer.interval = notification && notification.expireTimeout > 0 ? notification.expireTimeout : Config.notifyTimeout;
		toastTimer.restart();
	}

	Connections {
		target: Notifications

		function onArrived(notification) {
			root.toast(notification);
		}
	}

	Timer {
		id: toastTimer

		onTriggered: {
			if (!root.keyboardPopup)
				root.closePopup();
		}
	}

	popupPadding: 0
	popupKeyboard: root.keyboardPopup
	popupAlignRight: root.keyboardPopup === false

	popupContent: NotificationList {
		single: root.keyboardPopup === false
		onCloseRequested: root.closePopup()
	}
}
