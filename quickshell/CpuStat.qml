import QtQuick
import Quickshell.Io
import "config.js" as Config
import "helpers.js" as Helpers

BarStat {
	id: root

	property var prev: null
	property string lastRead: ""
	property var cores: []

	barColor: Helpers.mixColor(Config.cpuBase, Config.red, root.pct / 100)
	icon: Config.iconCpu
	value: Math.round(root.pct) + "%"

	function handleStat(text) {
		if (text === root.lastRead)
			return;
		root.lastRead = text;

		const first = root.prev === null;
		const now = Helpers.parseCpuStat(text);
		const load = Helpers.cpuPercents(root.prev, now);

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
}
