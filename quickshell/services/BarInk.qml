pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Item {
	id: root

	visible: false

	property bool bare: false
	property bool wantsBare: false
	property bool fading: false
	property var inks: ({})
	property var lastWalls: ({})
	property var fileMeans: ({})
	property var bareBars: []
	property var fileQueue: []
	property var filePending: null

	readonly property string statePath: Quickshell.shellDir + "/cache/bar-ink.json"

	function key(bar) {
		return bar && bar.screen ? bar.screen.name : "";
	}

	function pick(bar, id, normal) {
		if (!root.bare || !id)
			return normal;

		const ink = root.inks[root.key(bar)];

		return ink === "black" || ink === "white" ? ink : normal;
	}

	function toggle(bar) {
		if (root.bare) {
			root.stop();
			return;
		}

		root.bareBars = bar !== null ? [bar] : [];
		root.start();
	}

	function toggleAll(bars) {
		if (root.bare) {
			root.stop();
			return;
		}

		root.bareBars = (bars || []).slice();
		root.start();
	}

	function ensure(bar) {
		if (bar === null || root.bareBars.indexOf(bar) >= 0)
			return;

		root.bareBars = root.bareBars.concat([bar]);
		root.lastWalls = {};
	}

	function persist() {
		stateWrite.running = false;
		stateWrite.command = Shell.writeCommand(root.statePath, JSON.stringify({ bare: root.bare, means: root.fileMeans }));
		stateWrite.running = true;
	}

	function stop() {
		root.fade();
		root.bare = false;
		root.bareBars = [];
		root.fileQueue = [];
		root.filePending = null;
		root.persist();
	}

	function start() {
		root.lastWalls = {};
		root.persist();
		root.poll();
	}

	function poll() {
		if (!queryRun.running)
			queryRun.running = true;
	}

	function queueInk(bar, path) {
		const key = path + "|" + bar.screen.width + "x" + bar.screen.height;

		if (root.fileMeans[key] !== undefined) {
			root.applyMean(bar, root.fileMeans[key]);
			return;
		}

		root.fileQueue = root.fileQueue.concat([{ bar: bar, path: path, key: key }]);
		root.pumpFile();
	}

	function pumpFile() {
		if (root.filePending !== null || root.fileQueue.length === 0)
			return;

		const job = root.fileQueue[0];

		root.fileQueue = root.fileQueue.slice(1);

		if (job.bar === null || !job.bar.screen)
			return root.pumpFile();

		root.filePending = job.bar;
		fileRun.fileKey = job.key;
		fileRun.running = false;
		fileRun.command = BarInkLib.fileMeanCommand(job.path, job.bar.screen.width, job.bar.screen.height, job.bar.implicitHeight);
		fileRun.running = true;
	}

	function fade() {
		root.fading = true;
		fadeTimer.restart();
	}

	function applyMean(bar, mean) {
		if (root.bareBars.indexOf(bar) < 0 || mean < 0)
			return;

		const k = root.key(bar);
		const current = root.inks[k] || "";
		const ink = BarInkLib.settleInk(mean, current);

		if (ink === current && root.bare)
			return;

		const next = Object.assign({}, root.inks);

		next[k] = ink;
		root.fade();
		root.inks = next;
		root.bare = true;
		root.persist();
	}

	Timer {
		id: fadeTimer

		interval: Config.barFadeMs
		repeat: false
		running: false

		onTriggered: root.fading = false
	}

	Timer {
		id: queryTimer

		interval: 500
		repeat: true
		running: root.bareBars.length > 0
		triggeredOnStart: true

		onTriggered: root.poll()
	}

	Process {
		id: queryRun

		command: ["awww", "query"]

		stdout: StdioCollector {
			onStreamFinished: queryRun.handleQuery(text)
		}

		function handleQuery(text) {
			const next = Object.assign({}, root.lastWalls);

			for (let i = 0; i < root.bareBars.length; i++) {
				const bar = root.bareBars[i];

				if (!bar || !bar.screen)
					continue;

				const name = bar.screen.name;
				const path = BarInkLib.wallpaperForScreen(text, name);

				if (path === "" || path === root.lastWalls[name])
					continue;

				next[name] = path;
				root.queueInk(bar, path);
			}

			root.lastWalls = next;
		}
	}

	Process {
		id: fileRun

		property string fileKey: ""

		stdout: StdioCollector {
			onStreamFinished: fileRun.handleFile(text)
		}

		function handleFile(text) {
			const bar = root.filePending;

			root.filePending = null;

			if (bar === null) {
				root.pumpFile();
				return;
			}

			const mean = BarInkLib.parseMean(text);

			if (mean >= 0) {
				const next = Object.assign({}, root.fileMeans);

				next[fileRun.fileKey] = mean;
				root.fileMeans = next;
				root.persist();
			}

			root.applyMean(bar, mean);
			root.pumpFile();
		}
	}

	Process {
		id: stateWrite
	}

	FileView {
		id: stateFile

		path: root.statePath
		blockLoading: true
		printErrors: false

		onLoaded: {
			try {
				const state = JSON.parse(stateFile.text());

				root.wantsBare = state.bare === true;
				root.fileMeans = state.means || {};
			} catch (e) {
				root.wantsBare = false;
			}
		}
	}

	Component.onCompleted: stateFile.reload()
}
