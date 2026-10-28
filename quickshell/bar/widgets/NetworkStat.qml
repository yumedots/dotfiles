import QtQuick
import qs
import qs.ui
import qs.services
import "../../tooltips"

BarStat {
	id: root

	inkId: "network"

	readonly property var net: Yudae.network
	readonly property bool isWifi: root.net.kind === "wifi"
	readonly property int wifiStep: Calc.clamp(root.net.bars || 0, 1, 4) - 1
	readonly property string wifiIcon: Config.networkWifiIcons[root.wifiStep]

	property bool testPending: false

	mode: "icon"
	barColor: Config.mono ? Config.networkBase : Config.networkBaseMono
	textColor: root.barColor
	icon: root.isWifi ? root.wifiIcon : Config.networkLanIcon

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
