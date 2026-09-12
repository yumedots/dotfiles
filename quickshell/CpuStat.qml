import QtQuick
import Quickshell.Io
import "theme.js" as Theme

BarStat {
	id: root

	property real prevTotal: -1
	property real prevIdle: -1
	property bool waitingForSecondSample: false
	property string lastRead: ""

	barColor: Theme.mixColor(Theme.cpuBase, Theme.red, root.pct / 100)
	icon: Theme.iconCpu
	value: Math.round(root.pct) + "%"

	function sample(text) {
		const fields = text.split("\n")[0].split(/\s+/);
		let total = 0;
		let idle = 0;
		for (let i = 1; i < fields.length; i++) {
			const n = parseFloat(fields[i]);
			if (isNaN(n))
				continue;
			total += n;
			if (i === 4 || i === 5)
				idle += n;
		}
		return [total, idle];
	}

	function handleStat(text) {
		if (text === root.lastRead)
			return;
		root.lastRead = text;

		const s = sample(text);
		if (!root.waitingForSecondSample) {
			root.prevTotal = s[0];
			root.prevIdle = s[1];
			root.waitingForSecondSample = true;
			secondSample.restart();
			return;
		}

		const dt = s[0] - root.prevTotal;
		const di = s[1] - root.prevIdle;
		root.waitingForSecondSample = false;
		if (dt > 0)
			root.pct = 100 * (1 - di / dt);
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
