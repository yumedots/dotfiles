import QtQuick
import Quickshell.Io
import qs.ui
import qs
import "../../tooltips"

BarStat {
	id: root

	property var prev: null
	property string lastRead: ""
	property var cores: []

	barColor: Color.mixColor(Config.cpuBase, Config.red, root.pct / 100)
	icon: Config.iconCpu
	value: Math.round(root.pct) + "%"

	function handleStat(text) {
		if (text === root.lastRead)
			return;
		root.lastRead = text;

		const first = root.prev === null;
		const now = System.parseCpuStat(text);
		const load = System.cpuPercents(root.prev, now);

		root.prev = now;
		root.cores = load.cores;
		root.pct = load.all;

		if (first)
			secondSample.restart();
	}

	function refresh() {
		statFile.reload();
	}

	FileView {
		id: statFile
		path: "/proc/stat"
		blockLoading: true
		onTextChanged: root.handleStat(statFile.text())
		onLoaded: root.handleStat(statFile.text())
	}

	Timer {
		interval: 2000
		running: true
		repeat: true
		triggeredOnStart: true
		onTriggered: statFile.reload()
	}

	Timer {
		id: secondSample
		interval: 150
		repeat: false
		onTriggered: statFile.reload()
	}

	popupContent: CpuMonitor {
		id: monitor

		source: root
		onCloseRequested: root.closePopup()
	}
}
