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
	property var pendingFile: null
	property real watchBase: -1
	property int watchTries: 0
	property var filePending: null
	property var fileQueue: []
	property var fileMeans: ({})
	property var bareBars: []
	property var queue: []
	property var walls: ({})

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

	function seed(bar) {
		if (bar === null || !bar.screen)
			return false;

		const wall = root.walls[bar.screen.name];

		if (!wall)
			return false;

		const key = wall + "|" + bar.screen.width + "x" + bar.screen.height;

		if (root.fileMeans[key] === undefined)
			return false;

		root.applyMean(bar, root.fileMeans[key]);
		return true;
	}

	function ensure(bar) {
		if (bar === null || root.bareBars.indexOf(bar) >= 0)
			return;

		root.bareBars.push(bar);
		root.bare = true;

		if (!root.seed(bar))
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
		root.queue = [];

		for (let i = 0; i < root.bareBars.length; i++) {
			if (!root.seed(root.bareBars[i]))
				root.queue.push(root.bareBars[i]);
		}

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

		root.pendingFile = path;

		for (let i = 0; i < root.bareBars.length; i++) {
			const bar = root.bareBars[i];

			if (bar === null || !bar.screen)
				continue;

			const key = path + "|" + bar.screen.width + "x" + bar.screen.height;

			if (root.fileMeans[key] === undefined)
				root.fileQueue.push({ bar: bar, path: path, key: key });
		}

		root.pumpFile();
		root.watchBase = -1;
		root.watchTries = 0;
		root.sampleBar();
	}

	function sampleBar() {
		if (root.bareBars.length === 0 || watchRun.running)
			return;

		const bar = root.bareBars[0];

		if (bar === null || !bar.screen)
			return;

		watchRun.command = [Quickshell.shellDir + "/scripts/bar-ink-sample", bar.screen.name, "" + Math.max(1, Math.round(bar.implicitHeight))];
		watchRun.running = true;
	}

	function answerFile() {
		const path = root.pendingFile;

		root.pendingFile = null;
		watchTimer.stop();

		if (!path)
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

		interval: Config.barInkFadeMs
		repeat: false
		running: false

		onTriggered: root.fading = false
	}

	Timer {
		id: watchTimer

		interval: 120
		repeat: true
		running: false

		onTriggered: {
			if (root.watchTries >= 30) {
				root.answerFile();
				return;
			}

			root.watchTries++;
			root.sampleBar();
		}
	}

	Process {
		id: watchRun

		stdout: StdioCollector {
			onStreamFinished: watchRun.handleWatch(text)
		}

		function handleWatch(text) {
			const mean = BarInkLib.parseMean(text);

			if (mean < 0) {
				root.answerFile();
				return;
			}

			if (root.watchBase < 0) {
				root.watchBase = mean;
				root.watchTries = 0;
				watchTimer.restart();
				return;
			}

			if (Math.abs(mean - root.watchBase) > 0.04 || root.watchTries >= 30) {
				watchTimer.stop();
				root.answerFile();
				return;
			}

			root.watchTries++;
		}
	}

	Timer {
		id: confirmTimer

		interval: 600
		repeat: false
		running: false

		onTriggered: root.pump()
	}

	Timer {
		id: queryTimer

		interval: 10000
		repeat: true
		running: true
		triggeredOnStart: true

		onTriggered: {
			if (!queryRun.running)
				queryRun.running = true;
		}
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
		id: queryRun

		stdout: StdioCollector {
			onStreamFinished: queryRun.handleQuery(text)
		}

		function handleQuery(text) {
			const walls = {};

			for (let i = 0; i < root.bareBars.length; i++) {
				const bar = root.bareBars[i];

				if (bar && bar.screen)
					walls[bar.screen.name] = BarInkLib.wallpaperForScreen(text, bar.screen.name);
			}

			root.walls = walls;
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
		id: pathFile

		path: Quickshell.shellDir + "/cache/bar-ink-path.txt"
		blockLoading: true
		printErrors: false

		onFileChanged: pathFile.reload()

		onLoaded: {
			const path = pathFile.text().trim();

			if (path !== "")
				root.reinkFile(path);
		}
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
