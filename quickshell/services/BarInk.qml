pragma Singleton

import QtQuick
import Quickshell
import qs

Item {
	id: root

	visible: false

	property bool fading: false
	property var bareBars: []
	property var bars: []
	property var inks: ({})

	readonly property var state: Yudae.ink || ({})
	readonly property bool bare: state.bare === true
	readonly property bool wantsBare: root.bare
	readonly property int savedBand: state.band || 0
	readonly property int fadeMs: Math.round(Config.wallpaperTransitionMs / 2)

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

		root.fade();
		root.bareBars = bar !== null ? [bar] : [];
		root.send(true);
	}

	function toggleAll(all) {
		if (root.bare) {
			root.stop();
			return;
		}

		root.fade();
		root.bareBars = (all || []).slice();
		root.send(true);
	}

	function ensure(bar) {
		if (bar === null || root.bareBars.indexOf(bar) >= 0)
			return;

		root.bareBars = root.bareBars.concat([bar]);

		if (!root.bare)
			root.send(true);
	}

	function register(bar) {
		if (bar && root.bars.indexOf(bar) < 0)
			root.bars = root.bars.concat([bar]);
	}

	function unregister(bar) {
		root.bars = root.bars.filter(function (b) { return b !== bar; });
	}

	function stop() {
		root.fade();
		root.bareBars = [];
		root.send(false);
	}

	function send(bare) {
		Yudae.send({ cmd: { ink: { band: root.bandPx(), bare: bare } } });
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

	function syncInks() {
		const next = root.state.inks || ({});
		const keys = Object.keys(next);

		if (keys.length === Object.keys(root.inks).length && keys.every(function (name) { return root.inks[name] === next[name]; }))
			return;

		root.fade();
		root.inks = next;
	}

	function fade() {
		root.fading = true;
		fadeTimer.restart();
	}

	onStateChanged: root.syncInks()

	Timer {
		id: fadeTimer

		interval: root.fadeMs
		repeat: false
		running: false

		onTriggered: root.fading = false
	}
}
