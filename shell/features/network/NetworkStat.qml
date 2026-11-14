import QtQuick
import qs
import qs.ui
import qs.services

BarStat {
	id: root

	inkId: "network"

	readonly property var net: Yudae.network
	readonly property bool isWifi: root.net.kind === "wifi"
	readonly property bool linked: root.net.connected === true && (root.net.kind || "") !== ""
	readonly property string wifiIcon: Config.wifiGlyph(root.net.bars)

	property bool testPending: false

	mode: "icon"
	barColor: Config.mono ? Config.networkBaseMono : Config.networkBase
	textColor: root.barColor
	icon: root.isWifi ? root.wifiIcon : (!root.linked && root.net.hasWifi === true ? Config.iconWifiOff : Config.iconEthernet)

	function requestSpeedTest() {
		if (!root.popupVisible) {
			if (root.bar)
				root.bar.activateWidget(root, false);
			else
				root.openPopup();
		}

		Handoff.run(function () {
			if (!root.testPending)
				root.testPending = true;
		});
	}

	function clearSpeedTest() {
		root.testPending = false;
	}

	popupContent: Component {
		NetworkMonitor {
			id: monitor

			source: root
			onCloseRequested: root.closePopup()
		}
	}
}
