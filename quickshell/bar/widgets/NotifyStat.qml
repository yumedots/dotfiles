import QtQuick
import qs.ui
import qs.services
import qs
import "../../tooltips"

BarStat {
	id: root

	inkId: "notify"

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

	function clicked() {
		if (root.bar)
			root.bar.activateWidget(root, true);
		else
			root.openPopup();
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

		if (notification && notification.urgent === true) {
			toastTimer.stop();
			return;
		}

		toastTimer.interval = notification && notification.timeout > 0 ? notification.timeout : Config.notifyTimeout;
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

	popupKeyboard: root.keyboardPopup
	popupAlignRight: root.keyboardPopup === false
	popupCentered: true
	popupAlwaysCentered: true
	popupPreload: true
	popupSlide: root.keyboardPopup === false

	popupContent: Component {
		NotificationList {
			single: root.keyboardPopup === false
			closing: !root.popupVisible
			onCloseRequested: root.closePopup()
		}
	}
}
