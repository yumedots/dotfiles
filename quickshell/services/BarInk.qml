pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Item {
	id: root

	visible: false

	property bool bare: false
	property var inks: ({})
	property var pendingBar: null

	function key(bar, id) {
		const screen = bar && bar.screen ? bar.screen.name : "";

		return screen + "/" + id;
	}

	function pick(bar, id, normal) {
		if (!root.bare || !id)
			return normal;

		const ink = root.inks[root.key(bar, id)];

		return ink === "black" || ink === "white" ? ink : normal;
	}

	function toggle(bar) {
		if (root.bare) {
			root.bare = false;
			root.pendingBar = null;
			return;
		}

		root.pendingBar = bar;
		root.bare = true;
		monRun.command = ["hyprctl", "monitors", "-j"];

		if (!monRun.running)
			monRun.running = true;
	}

	function applyMean(bar, mean) {
		const ink = mean < 0 ? "" : BarInkLib.inkFor(mean);
		const next = {};
		const ids = Object.keys(bar.widgets || {});

		for (let i = 0; i < ids.length; i++) {
			if (bar.widgets[ids[i]] && bar.widgets[ids[i]].width > 0)
				next[root.key(bar, ids[i])] = ink;
		}

		root.inks = next;
		root.pendingBar = null;
	}

	Process {
		id: monRun

		property string out: ""

		stdout: StdioCollector {
			onStreamFinished: monRun.out = text
		}

		onExited: {
			const bar = root.pendingBar;

			if (exitCode !== 0 || bar === null || !bar.screen) {
				root.pendingBar = null;
				return;
			}

			const geo = BarInkLib.monitorGeo(monRun.out, bar.screen.name);

			if (geo === null) {
				root.pendingBar = null;
				return;
			}

			stripRun.command = BarInkLib.stripCommand(geo.x, geo.y, geo.w, bar.implicitHeight);

			if (!stripRun.running)
				stripRun.running = true;
		}
	}

	Process {
		id: stripRun

		property string out: ""

		stdout: StdioCollector {
			onStreamFinished: stripRun.out = text
		}

		onExited: {
			const bar = root.pendingBar;

			root.pendingBar = null;

			if (exitCode !== 0 || bar === null)
				return;

			root.applyMean(bar, BarInkLib.parseMean(stripRun.out));
		}
	}
}
