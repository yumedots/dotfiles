import QtQuick
import Quickshell.Io
import qs
import qs.ui
import qs.services
import "../../tooltips"

BarStat {
	id: root

	property var prev: null
	property var counts: ({})
	property var history: []
	property string netRaw: ""
	property string devRaw: ""
	property string infoRaw: ""
	property string wifiRaw: ""
	property real peak: 1
	property bool scanned: false

	readonly property var devs: Network.parseDevs(root.devRaw)
	readonly property var dev: Network.pickDev(root.devs)
	readonly property string iface: root.dev ? root.dev.device : ""
	readonly property string kind: root.dev ? root.dev.type : ""
	readonly property bool isWifi: root.kind === "wifi"
	readonly property var rates: Network.rateBetween(root.prev, root.counts, root.iface, Config.networkPollMs / 1000)
	readonly property real down: root.rates.down
	readonly property real up: root.rates.up
	readonly property var info: Network.deviceInfo(root.infoRaw)
	readonly property string ip: root.info.ip
	readonly property int signal: Network.currentSignal(root.wifiRaw)
	readonly property int bars: Network.signalBars(root.signal)
	readonly property bool linked: root.dev !== null && root.dev.state.indexOf("connected") === 0
	readonly property int wifiStep: Util.clamp(root.bars, 1, 4) - 1
	readonly property string wifiIcon: Config.networkWifiIcons[root.wifiStep]

	barColor: Util.pick(Config.mono, Config.networkBase, Config.networkBaseMono)
	textColor: root.barColor
	icon: root.isWifi ? root.wifiIcon : Config.networkLanIcon

	function handleNet(text) {
		const now = Network.parseRates(text);

		root.prev = root.counts;
		root.counts = now;
	}

	function refresh() {
		netFile.reload();
		devRun.reload();
	}

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

	onIfaceChanged: refreshInfo()
	onDownChanged: pushHistory()
	onPopupVisibleChanged: {
		if (root.popupVisible)
			root.scan();
	}

	function pushHistory() {
		const next = root.history.concat([{ down: root.down, up: root.up }]);

		root.history = next.slice(Math.max(0, next.length - Config.networkHistory));
		root.peak = Math.max(1, root.down, root.up, root.peak * 0.98);
	}

	Component.onCompleted: {
		refresh();
		devRun.reload();
	}

	FileView {
		id: netFile

		path: "/proc/net/dev"
		blockLoading: true

		onTextChanged: root.handleNet(netFile.text())
		onLoaded: root.handleNet(netFile.text())
	}

	Timer {
		interval: Config.networkPollMs
		running: true
		repeat: true
		triggeredOnStart: true

		onTriggered: {
			netFile.reload();
			devRun.reload();
		}
	}

	Request {
		id: devRun

		command: ["nmcli", "-t", "-e", "no", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"]

		function reload() {
			if (!devRun.running)
				devRun.running = true;
		}

		onDone: function (text) { root.devRaw = text; }
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

		command: Network.listCommand()

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
