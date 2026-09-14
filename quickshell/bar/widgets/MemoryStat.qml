import QtQuick
import Quickshell.Io
import qs.ui
import qs

BarStat {
	id: root

	property var memory: null

	readonly property real usedGB: root.memory ? root.memory.used / 1024 / 1024 : 0

	barColor: Helpers.dangerColor(Config.memoryBase, Config.memoryWarn, Config.memoryDanger, Config.memoryWarnAt, Config.memoryDangerAt, root.pct)
	icon: Config.iconMemory
	value: root.usedGB.toFixed(1) + "G"

	function handleMeminfo(text) {
		const mem = Helpers.parseMeminfo(text);

		if (mem.total <= 0)
			return;

		root.memory = mem;
		root.pct = mem.pct;
	}

	function refresh() {
		memFile.reload();
	}

	FileView {
		id: memFile

		path: "/proc/meminfo"
		blockLoading: true

		onTextChanged: root.handleMeminfo(memFile.text())
		onLoaded: root.handleMeminfo(memFile.text())
	}

	Timer {
		interval: 1000
		running: true
		repeat: true
		triggeredOnStart: true
		onTriggered: memFile.reload()
	}
}
