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
	property string currentInk: ""
	property var inks: ({})
	property var pendingBar: null
	property var filePending: null
	property var fileQueue: []
	property var fileMeans: ({})
	property var bareBars: []
	property var queue: []

	readonly property string statePath: Quickshell.shellDir + "/cache/bar-ink.json"

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

		root.bareBars.push(bar);
		root.bare = true;
		root.queue.push(bar);
		sampleSoon.restart();
	}

	function persist() {
		stateWrite.command = Shell.writeCommand(root.statePath, JSON.stringify({ bare: root.bare, means: root.fileMeans }));

		if (!stateWrite.running)
			stateWrite.running = true;
	}

	function stop() {
		root.fade();
		root.bare = false;
		root.pendingBar = null;
		root.filePending = null;
		root.bareBars = [];
		root.queue = [];
		root.fileQueue = [];
		root.persist();
	}

	function start() {
		root.bare = true;
		root.queue = root.bareBars.slice();
		root.persist();
		sampleSoon.restart();
	}

	function pump() {
		if (root.pendingBar !== null || root.queue.length === 0)
			return;

		root.detect(root.queue[0]);
	}

	function poke() {
		if (!root.bare)
			return;

		root.queue = root.bareBars.slice();
		confirmTimer.restart();
	}

	function reinkFile(path) {
		if (!root.bare || !path)
			return;

		for (let i = 0; i < root.bareBars.length; i++) {
			const bar = root.bareBars[i];

			if (bar === null || !bar.screen)
				continue;

			const key = path + "|" + bar.screen.width + "x" + bar.screen.height;

			if (root.fileMeans[key] !== undefined)
				root.applyMean(bar, root.fileMeans[key]);
			else
				root.fileQueue.push({ bar: bar, path: path, key: key });
		}

		root.pumpFile();
	}

	function pumpFile() {
		if (root.filePending !== null || root.fileQueue.length === 0)
			return;

		const job = root.fileQueue.shift();

		if (job.bar === null || !job.bar.screen)
			return;

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

	function detect(bar) {
		root.pendingBar = bar;

		if (bar === null || !bar.screen) {
			root.pendingBar = null;
			return;
		}

		sampleRun.running = false;
		sampleRun.command = [Quickshell.shellDir + "/scripts/bar-ink-sample", bar.screen.name, "" + Math.max(1, Math.round(bar.implicitHeight))];
		sampleRun.running = true;
	}

	function applyMean(bar, mean) {
		if (root.bareBars.indexOf(bar) < 0) {
			root.pendingBar = null;
			return;
		}

		const ink = mean < 0 ? "" : BarInkLib.settleInk(mean, root.currentInk);

		if (ink === "") {
			root.pendingBar = null;

			const at = root.queue.indexOf(bar);

			if (at >= 0)
				root.queue.splice(at, 1);

			root.pump();
			return;
		}
		const next = Object.assign({}, root.inks);
		const ids = Object.keys(bar.widgets || {});
		let same = ink !== "";

		for (let i = 0; i < ids.length; i++) {
			if (bar.widgets[ids[i]] && bar.widgets[ids[i]].width > 0) {
				next[root.key(bar, ids[i])] = ink;

				if (root.inks[root.key(bar, ids[i])] !== ink)
					same = false;
			}
		}

		root.pendingBar = null;

		const at = root.queue.indexOf(bar);

		if (at >= 0)
			root.queue.splice(at, 1);

		if (same)
			return;

		root.fade();
		root.inks = next;
		root.currentInk = ink;
		root.bare = true;
		root.pump();
	}

	Timer {
		id: fadeTimer

		interval: Config.popupSlideMs
		repeat: false
		running: false

		onTriggered: root.fading = false
	}

	Timer {
		id: confirmTimer

		interval: 600
		repeat: false
		running: false

		onTriggered: root.pump()
	}

	Timer {
		id: sampleSoon

		interval: 300
		repeat: false
		running: false

		onTriggered: root.pump()
	}

	Timer {
		id: sampleTimer

		interval: 30000
		repeat: true
		running: true

		onTriggered: {
			if (!root.bare)
				return;

			root.pendingBar = null;
			root.queue = root.bareBars.slice();
			root.pump();
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
		id: sampleRun

		stdout: StdioCollector {
			onStreamFinished: sampleRun.handleSample(text)
		}

		function handleSample(text) {
			const bar = root.pendingBar;

			root.pendingBar = null;

			if (bar === null)
				return;

			root.applyMean(bar, BarInkLib.parseMean(text));
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
