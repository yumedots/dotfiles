import QtQuick
import Quickshell.Io
import qs.ui
import qs

ProcessPanel {
	id: root

	property var battery: root.source ? root.source.battery : null
	property var governors: root.source ? root.source.governors : []
	property string governor: root.source ? root.source.governor : ""
	property var info: ({ threads: 0 })
	property real watts: 0
	property real raplBefore: -1
	property real raplAt: 0
	property real raplMax: 0

	readonly property color accentInk: Util.pick(Config.mono, Config.powerBase, Config.powerBaseMono)
	readonly property color warnInk: Util.pick(Config.mono, Config.powerWarn, Config.powerWarnMono)
	readonly property color dangerInk: Util.pick(Config.mono, Config.powerDanger, Config.powerDangerMono)
	readonly property int threads: root.info.threads > 0 ? root.info.threads : 1
	readonly property string headline: root.headlineText()
	readonly property int governorIndex: Math.max(0, root.governors.indexOf(root.governor))

	title: Config.powerTitle
	showTotal: root.headline !== ""
	totalOverride: root.headline
	detailColor: root.dangerColorFor(root.battery ? root.battery.pct : 100)
	listInk: root.accentInk
	totalInk: root.dangerColorFor(root.battery ? root.battery.pct : 100)
	panelWidth: Config.powerTooltipWidth
	panelPadding: Config.powerTooltipPadding
	topCount: Config.powerTopCount
	psField: "pcpu"
	rowText: (value) => root.energyText(value)
	rowColor: (value) => root.dangerColorFor(value)

	function dangerColorFor(load) {
		return Color.dangerColor(root.accentInk, root.warnInk, root.dangerInk, Config.powerWarnAt, Config.powerDangerAt, load);
	}

	function headlineText() {
		const parts = [];

		if (root.battery)
			parts.push(Math.round(root.battery.pct) + "%" + (root.battery.charging ? " charging" : ""));

		if (root.watts > 0)
			parts.push(root.watts.toFixed(1) + "W");

		return parts.join(" · ");
	}

	function energyText(pcpu) {
		if (root.watts > 0) {
			const share = System.energyShare(root.watts, pcpu, root.threads);

			return (share >= 1 ? share.toFixed(1) : share.toFixed(2)) + "W";
		}

		return pcpu.toFixed(1) + "%";
	}

	function handleRapl(text) {
		const now = parseFloat(text);
		const at = Date.now();

		if (!(now >= 0))
			return;

		if (root.raplBefore >= 0 && at > root.raplAt) {
			let delta = now - root.raplBefore;

			if (delta < 0 && root.raplMax > 0)
				delta += root.raplMax;

			if (delta >= 0)
				root.watts = System.raplWatts(0, delta, at - root.raplAt);
		}

		root.raplBefore = now;
		root.raplAt = at;
	}

	FileView {
		id: cpuInfoFile

		path: "/proc/cpuinfo"
		blockLoading: true

		onLoaded: root.info = System.parseCpuInfo(cpuInfoFile.text())
	}

	FileView {
		id: raplMaxFile

		path: "/sys/class/powercap/intel-rapl:0/max_energy_range_uj"
		blockLoading: true

		onLoaded: root.raplMax = parseFloat(raplMaxFile.text()) || 0
	}

	FileView {
		id: raplFile

		path: "/sys/class/powercap/intel-rapl:0/energy_uj"
		blockLoading: true

		onLoaded: root.handleRapl(raplFile.text())
	}

	Timer {
		interval: 5000
		running: root.Window.window ? root.Window.window.visible : false
		repeat: true
		triggeredOnStart: true
		onTriggered: raplFile.reload()
	}

	viz: [
		Item {
			width: parent.width
			height: Math.max(govTitle.implicitHeight, govCurrent.implicitHeight)

			Text {
				id: govTitle

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.listInk
				text: Config.powerGovernorTitle
			}

			Text {
				id: govCurrent

				anchors.right: parent.right
				elide: Text.ElideRight
				width: Math.min(implicitWidth, parent.width - govTitle.width - 8)

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.accentInk
				text: govStep.hoverLabel !== "" ? govStep.hoverLabel : root.governor
			}
		},

		StepBar {
			id: govStep

			width: parent.width
			model: root.governors
			selected: root.governorIndex
			ink: root.accentInk
			onPick: (next) => root.governorPicked(String(next))
		}
	]

	signal governorPicked(string governor)
}
