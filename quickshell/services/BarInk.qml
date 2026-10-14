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
	property var means: ({})
	property var bareBars: []
	property var bars: []
	property var mtimes: ({})
	property var jobs: []
	property var job: null
	property string wall: ""
	property string wallDir: ""
	property bool persistPending: false

	readonly property string statePath: Quickshell.shellDir + "/cache/bar-ink.json"
	readonly property string settingsPath: Quickshell.shellDir + "/cache/settings.lua"

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

	function toggleAll(all) {
		if (root.bare) {
			root.stop();
			return;
		}

		root.bareBars = (all || []).slice();
		root.start();
	}

	function ensure(bar) {
		if (bar === null || root.bareBars.indexOf(bar) >= 0)
			return;

		root.bareBars = root.bareBars.concat([bar]);
		scanTimer.restart();
	}

	function register(bar) {
		if (bar && root.bars.indexOf(bar) < 0) {
			root.bars = root.bars.concat([bar]);
			scanTimer.restart();
		}
	}

	function unregister(bar) {
		root.bars = root.bars.filter(function (b) { return b !== bar; });
	}

	function persist() {
		stateWrite.running = false;
		stateWrite.command = Shell.writeCommand(root.statePath, JSON.stringify({ bare: root.bare, means: root.means }));
		stateWrite.running = true;
		root.persistPending = false;
	}

	function stop() {
		root.fade();
		root.bare = false;
		root.bareBars = [];
		root.jobs = [];
		root.persist();
	}

	function start() {
		root.persist();
		root.runScan();
	}

	function runScan() {
		if (root.wallDir === "")
			return;

		scanRun.running = false;
		scanRun.command = BarInkLib.wallScanCommand(root.wallDir.replace(/^~/, Quickshell.env("HOME")), Config.wallpaperDepth);
		scanRun.running = true;
	}

	function fade() {
		root.fading = true;
		fadeTimer.restart();
	}

	function meanFor(bar) {
		const mtime = root.mtimes[root.wall];

		if (mtime === undefined || !bar.screen || !(bar.implicitHeight > 0))
			return -1;

		const mean = root.means[BarInkLib.keyFor(root.wall, mtime, bar.screen.width, bar.screen.height, bar.implicitHeight)];

		return mean === undefined ? -1 : mean;
	}

	function applyCurrent() {
		for (let i = 0; i < root.bareBars.length; i++) {
			const mean = root.meanFor(root.bareBars[i]);

			if (mean >= 0)
				root.applyMean(root.bareBars[i], mean);
		}
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

	function handleList(text) {
		const files = BarInkLib.parseList(text);
		const mtimes = {};
		const valid = {};

		for (let i = 0; i < files.length; i++) {
			mtimes[files[i].path] = files[i].mtime;
			valid[files[i].path + "|" + files[i].mtime] = true;
		}

		root.mtimes = mtimes;

		if (files.length === 0)
			return root.applyCurrent();

		const next = {};
		let pruned = false;

		for (const k in root.means) {
			if (valid[BarInkLib.fileOf(k)])
				next[k] = root.means[k];
			else
				pruned = true;
		}

		const queue = [];

		for (let b = 0; b < root.bars.length; b++) {
			const bar = root.bars[b];

			if (!bar.screen || !(bar.implicitHeight > 0))
				continue;

			for (let i = 0; i < files.length; i++) {
				const k = BarInkLib.keyFor(files[i].path, files[i].mtime, bar.screen.width, bar.screen.height, bar.implicitHeight);

				if (next[k] === undefined)
					queue.push({ key: k, path: files[i].path, w: bar.screen.width, h: bar.screen.height, barPx: bar.implicitHeight });
			}
		}

		if (pruned || queue.length > 0) {
			root.means = next;
			root.persistPending = root.persistPending || pruned;
		}

		root.jobs = queue;
		root.pumpJob();
	}

	function pumpJob() {
		if (sampleRun.running)
			return;

		if (root.jobs.length === 0) {
			if (root.persistPending)
				root.persist();

			return root.applyCurrent();
		}

		root.job = root.jobs[0];
		root.jobs = root.jobs.slice(1);
		sampleRun.running = false;
		sampleRun.command = BarInkLib.fileMeanCommand(root.job.path, root.job.w, root.job.h, root.job.barPx);
		sampleRun.running = true;
	}

	Timer {
		id: fadeTimer

		interval: Config.barFadeMs
		repeat: false
		running: false

		onTriggered: root.fading = false
	}

	Timer {
		id: scanTimer

		interval: 300
		repeat: false

		onTriggered: root.runScan()
	}

	Process {
		id: scanRun

		stdout: StdioCollector {
			onStreamFinished: root.handleList(text)
		}
	}

	Process {
		id: sampleRun

		stdout: StdioCollector {
			onStreamFinished: {
				const mean = BarInkLib.parseMean(text);

				if (mean >= 0) {
					const next = Object.assign({}, root.means);

					next[root.job.key] = mean;
					root.means = next;
					root.persistPending = true;
				}

				if (root.jobs.length === 0 && root.persistPending)
					root.persist();

				root.pumpJob();
			}
		}
	}

	Process {
		id: stateWrite
	}

	FileView {
		id: settingsFile

		path: root.settingsPath
		blockLoading: true
		printErrors: false
		watchChanges: true

		onLoaded: {
			const text = settingsFile.text();

			root.wall = Wallpaper.wallpaperFromText(text) || "";
			root.wallDir = Wallpaper.dirFromText(text) || Config.wallpaperDir;
			scanTimer.restart();
		}

		onFileChanged: settingsFile.reload()
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

	Component.onCompleted: {
		stateFile.reload();
		settingsFile.reload();
	}
}
