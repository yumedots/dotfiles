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
	property var bareBars: []
	property var bars: []
	property int savedBand: 0

	readonly property int fadeMs: Config.wallpaperTransitionMs
	readonly property string statePath: Quickshell.shellDir + "/cache/bar-ink.json"
	readonly property string settingsPath: Quickshell.shellDir + "/cache/settings.lua"
	readonly property string inkBin: "awww"

	function key(bar) {
		return bar && bar.screen ? bar.screen.name : "";
	}

	function pick(bar, id, normal) {
		if (!root.bare || !id)
			return normal;

		return root.inks[root.key(bar)] || normal;
	}

	function toggle(bar) {
		if (root.bare) {
			root.stop();
			return;
		}

		root.bareBars = bar !== null ? [bar] : [];
		root.bare = true;
		root.persist();
		root.queryDaemon();
	}

	function toggleAll(all) {
		if (root.bare) {
			root.stop();
			return;
		}

		root.bareBars = (all || []).slice();
		root.bare = true;
		root.persist();
		root.queryDaemon();
	}

	function ensure(bar) {
		if (bar === null || root.bareBars.indexOf(bar) >= 0)
			return;

		root.bareBars = root.bareBars.concat([bar]);
		root.bare = true;
		queryTimer.restart();
	}

	function register(bar) {
		if (bar && root.bars.indexOf(bar) < 0) {
			root.bars = root.bars.concat([bar]);
			queryTimer.restart();
		}
	}

	function unregister(bar) {
		root.bars = root.bars.filter(function (b) { return b !== bar; });
	}

	function persist() {
		stateWrite.running = false;
		stateWrite.command = Shell.writeCommand(root.statePath, JSON.stringify({ bare: root.bare, band: root.bandPx() || root.savedBand }));
		stateWrite.running = true;
	}

	function stop() {
		root.fade();
		root.bare = false;
		root.bareBars = [];
		root.persist();
	}

	function bandPx() {
		let px = 0;

		for (let i = 0; i < root.bars.length; i++) {
			const h = root.bars[i].implicitHeight;

			if (h > px)
				px = h;
		}

		return Math.ceil(px) || root.savedBand;
	}

	function queryDaemon() {
		queryRun.running = false;
		queryRun.command = [root.inkBin, "query"];
		queryRun.running = true;
	}

	function handleQuery(text) {
		const next = Object.assign({}, root.inks);
		let changed = false;

		for (let i = 0; i < root.bars.length; i++) {
			const bar = root.bars[i];

			if (!bar.screen)
				continue;

			const color = BarInkLib.queryColor(text, bar.screen.name);

			if (color !== "" && color !== next[bar.screen.name]) {
				next[bar.screen.name] = color;
				changed = true;
			}
		}

		if (changed) {
			root.fade();
			root.inks = next;
		}
	}

	function fade() {
		root.fading = true;
		fadeTimer.restart();
	}

	function follow() {
		followTimer.ticks = 0;
		followTimer.restart();
	}

	Timer {
		id: fadeTimer

		interval: root.fadeMs
		repeat: false
		running: false

		onTriggered: root.fading = false
	}

	Timer {
		id: queryTimer

		interval: 300
		repeat: false

		onTriggered: root.queryDaemon()
	}

	Timer {
		id: followTimer

		property int ticks: 0

		interval: 100
		repeat: true

		onTriggered: {
			root.queryDaemon();
			ticks++;
			if (ticks >= 20)
				stop();
		}
	}

	Timer {
		id: pollTimer

		interval: 2500
		repeat: true
		running: root.bare && root.bars.length > 0

		onTriggered: root.queryDaemon()
	}

	Process {
		id: queryRun

		stdout: StdioCollector {
			onStreamFinished: root.handleQuery(text)
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
				root.savedBand = state.band || 0;
			} catch (e) {
				root.wantsBare = false;
			}
		}
	}

	FileView {
		id: settingsFile

		path: root.settingsPath
		blockLoading: true
		printErrors: false
		watchChanges: true

		onLoaded: queryTimer.restart()

		onFileChanged: settingsFile.reload()
	}

	Component.onCompleted: {
		stateFile.reload();
		settingsFile.reload();
	}
}
