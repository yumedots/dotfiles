import QtQuick
import Quickshell.Io
import "config.js" as Config
import "helpers.js" as Helpers

BarStat {
	id: root

	property real usedGB: 0
	property real totalGB: 0

	barColor: Helpers.mixColor(Config.memoryBase, Config.red, root.pct / 100)
	icon: Config.iconMemory
	value: root.usedGB.toFixed(1) + "G"

	function handleMeminfo(text) {
		const vals = {};
		const lines = text.split("\n");
		for (let i = 0; i < lines.length; i++) {
			const fields = lines[i].split(/\s+/);
			if (fields.length < 2)
				continue;
			vals[fields[0].replace(/:$/, "")] = parseFloat(fields[1]);
		}

		const total = vals["MemTotal"] || 0;
		if (total <= 0)
			return;

		let available = vals["MemAvailable"] || 0;
		if (!available)
			available = (vals["MemFree"] || 0) + (vals["Buffers"] || 0) + (vals["Cached"] || 0);

		const used = total - available;
		root.usedGB = used / 1024 / 1024;
		root.totalGB = total / 1024 / 1024;
		root.pct = 100 * used / total;
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
