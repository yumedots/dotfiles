import QtQuick
import qs
import qs.ui
import qs.services
import "../../tooltips"

BarStat {
	id: root

	inkId: "network"

	readonly property var net: Yudae.network
	readonly property string iface: root.net.iface || ""
	readonly property string kind: root.net.kind || ""
	readonly property bool isWifi: root.kind === "wifi"
	readonly property bool linked: root.net.connected === true
	readonly property real down: root.net.down || 0
	readonly property real up: root.net.up || 0
	readonly property var history: root.net.history || []
	readonly property real peak: root.net.peak || 1
	readonly property int signal: root.net.signal || 0
	readonly property int bars: Network.signalBars(root.signal)
	readonly property int wifiStep: Util.clamp(root.bars, 1, 4) - 1
	readonly property string wifiIcon: Config.networkWifiIcons[root.wifiStep]
	readonly property string ip: root.net.ip || ""
	readonly property var dev: ({ device: root.iface, type: root.kind, state: root.linked ? "connected" : "", connection: root.net.ssid || root.iface })
	readonly property var info: ({ ip: root.net.ip || "", gateway: root.net.gateway || "", dns: root.net.dns || "" })

	property string infoRaw: ""
	property string wifiRaw: ""
	property bool testPending: false

	barColor: Util.pick(Config.mono, Config.networkBase, Config.networkBaseMono)
	textColor: root.barColor
	icon: root.isWifi ? root.wifiIcon : Config.networkLanIcon

	onIfaceChanged: refreshInfo()
	onPopupVisibleChanged: if (root.popupVisible) scan()

	function refreshInfo() {
		if (root.iface === "")
			return;

		infoRun.command = ["nmcli", "-t", "-f", "GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show", root.iface];
		infoRun.reload();
	}

	function scan() {
		if (root.iface === "")
			return;

		wifiRun.command = Network.scanCommand(root.iface);
		wifiRun.reload();
	}

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

	Request {
		id: infoRun

		function reload() {
			if (!infoRun.running)
				infoRun.running = true;
		}

		onDone: function (text) { root.infoRaw = text; }
	}

	Request {
		id: wifiRun

		function reload() {
			if (!wifiRun.running)
				wifiRun.running = true;
		}

		onDone: function (text) { root.wifiRaw = text; }
	}

	popupContent: Component {
		NetworkMonitor {
			id: monitor

			source: root
			onCloseRequested: root.closePopup()
		}
	}
}
