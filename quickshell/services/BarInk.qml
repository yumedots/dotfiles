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
	property var means: ({})
	property var bareBars: []
	property var sampleQueue: []
	property var sampling: null
	property string samplePath: ""
	property string sampleKey: ""

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
		stateWrite.command = Shell.writeCommand(root.statePath, JSON.stringify({ bare: root.bare, means: root.means }));
		stateWrite.running = true;
	}

	function stop() {
		root.fade();
		root.bare = false;
		root.bareBars = [];
		root.sampleQueue = [];
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

	function queueSample(bar) {
		if (root.sampleQueue.indexOf(bar) < 0)
			root.sampleQueue = root.sampleQueue.concat([bar]);

		root.pumpSample();
	}

	function pumpSample() {
		if (root.sampling !== null || root.sampleQueue.length === 0)
			return;

		const bar = root.sampleQueue[0];

		root.sampleQueue = root.sampleQueue.slice(1);

		if (!bar || !bar.screen || root.bareBars.indexOf(bar) < 0)
			return root.pumpSample();

		root.sampling = bar;
		root.samplePath = root.lastWalls[bar.screen.name] || "";
		statRun.running = false;
		statRun.command = ["stat", "-c", "%Y", root.samplePath];
		statRun.running = true;
	}

	function runSample() {
		const bar = root.sampling;

		if (bar === null)
			return root.pumpSample();

		sampleRun.running = false;
		sampleRun.command = BarInkLib.screenMeanCommand(bar.screen.name, bar.implicitHeight / bar.screen.height);
		sampleRun.running = true;
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
		const ink = BarInkLib.inkFor(mean);

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

	Timer {
		id: settleTimer

		interval: 3000
		repeat: false

		onTriggered: root.runSample()
	}

	Process {
		id: queryRun

		command: ["awww", "query"]

		stdout: StdioCollector {
			onStreamFinished: queryRun.handleQuery(text)
		}

		function handleQuery(text) {
			const next = Object.assign({}, root.lastWalls);
			const changed = [];

			for (let i = 0; i < root.bareBars.length; i++) {
				const bar = root.bareBars[i];

				if (!bar || !bar.screen)
					continue;

				const name = bar.screen.name;
				const path = BarInkLib.wallpaperForScreen(text, name);

				if (path === "" || path === root.lastWalls[name])
					continue;

				next[name] = path;
				changed.push(bar);
			}

			root.lastWalls = next;

			for (let i = 0; i < changed.length; i++)
				root.queueSample(changed[i]);
		}
	}

	Process {
		id: statRun

		stdout: StdioCollector {
			onStreamFinished: statRun.handleStat(text)
		}

		function handleStat(text) {
			const bar = root.sampling;
			const mtime = String(text || "").trim();

			if (bar === null)
				return root.pumpSample();

			root.sampleKey = mtime !== "" ? [bar.screen.width, bar.screen.height, bar.implicitHeight, root.samplePath, mtime].join("|") : "";

			const cached = root.means[root.sampleKey];

			if (root.sampleKey !== "" && cached !== undefined) {
				root.sampling = null;
				root.applyMean(bar, cached);
				return root.pumpSample();
			}

			settleTimer.restart();
		}
	}

	Process {
		id: sampleRun

		stdout: StdioCollector {
			onStreamFinished: sampleRun.handleSample(text)
		}

		function handleSample(text) {
			const bar = root.sampling;

			root.sampling = null;

			if (bar === null)
				return root.pumpSample();

			const mean = BarInkLib.parseMean(text);

			if (mean >= 0 && root.sampleKey !== "") {
				const prefix = root.sampleKey.slice(0, root.sampleKey.lastIndexOf("|") + 1);
				const next = {};

				for (const k in root.means) {
					if (k.indexOf(prefix) !== 0)
						next[k] = root.means[k];
				}

				next[root.sampleKey] = mean;
				root.means = next;
				root.persist();
			}

			root.applyMean(bar, mean);
			root.pumpSample();
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
				root.means = state.means || {};
			} catch (e) {
				root.wantsBare = false;
			}
		}
	}

	Component.onCompleted: stateFile.reload()
}
