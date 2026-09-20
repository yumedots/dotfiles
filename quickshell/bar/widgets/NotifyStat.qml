import QtQuick
import Quickshell.Services.Notifications
import qs.ui
import qs.services
import qs
import "../../tooltips"

BarStat {
	id: root

	property var bar: null
	property bool keyboardPopup: false

	icon: Config.iconBell
	value: String(Notifications.count)
	pct: Notifications.empty ? 0 : 100
	barColor: Notifications.empty ? Config.dim : Config.notifyBase
	textColor: Config.foreground
	dim: Notifications.empty
	sweep: true
	sweepWidth: Config.notifySweepWidth

	function wantKeyboard(flag) {
		root.keyboardPopup = flag === true;
	}

	function openPopup() {
		popup.open();
	}

	function closePopup() {
		popup.hideNow();
	}

	function isPopupOpen() {
		return popup.shown && root.keyboardPopup;
	}

	function toast(notification) {
		if (root.isPopupOpen()) {
			toastTimer.stop();
			return;
		}

		if (!popup.shown) {
			root.keyboardPopup = false;

			if (root.bar)
				root.bar.openExclusive(root);
			else
				popup.open();
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
				popup.close();
		}
	}

	Tooltip {
		id: popup

		anchorWindow: root.bar
		anchorItem: root
		contentPadding: 0
		wantsKeyboard: root.keyboardPopup
		alignRight: root.keyboardPopup === false

		NotificationList {
			single: root.keyboardPopup === false
			onCloseRequested: popup.close()
		}
	}
}
