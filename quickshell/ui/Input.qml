pragma Singleton

import QtQuick
import qs

QtObject {
	id: root

	readonly property var letters: ({ j: "down", k: "up", h: "left", l: "right" })
	readonly property var arrows: ({ [Qt.Key_Down]: "down", [Qt.Key_Up]: "up", [Qt.Key_Left]: "left", [Qt.Key_Right]: "right" })
	readonly property var aliases: ({
		[Qt.Key_Escape]: "escape",
		[Qt.Key_Return]: "accept",
		[Qt.Key_Enter]: "accept",
		[Qt.Key_Space]: "space"
	})

	readonly property var cancel: (event) => event.key === Qt.Key_Escape
	readonly property var accept: (event) => event.key === Qt.Key_Return || event.key === Qt.Key_Enter
	readonly property var pin: (event) => event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)
	readonly property var hint: (event) => event.text === Config.procHintKey

	readonly property var axis: (dir, step, page) => ({ down: step, up: -step, right: page, left: -page })[dir] || 0
	readonly property var direction: (event) => root.letters[event.text] || root.arrows[event.key] || ""
	readonly property var name: (event) => root.aliases[event.key] || root.direction(event) || event.text || ""
	readonly property var delta: (event, step, page) => root.axis(root.direction(event), step, page)
	readonly property var arrow: (event, step, page) => root.axis(root.arrows[event.key] || "", step, page)

	function act(event, keys) {
		const action = keys[root.name(event)];

		if (action === undefined)
			return false;

		action();
		event.accepted = true;
		return true;
	}

	function calendar(event, target) {
		return root.act(event, {
			escape: () => target.closeRequested(),
			left: () => target.step(-1),
			right: () => target.step(1),
			up: () => target.step(-7),
			down: () => target.step(7),
			s: () => target.stepMonths(-1),
			d: () => target.stepMonths(1),
			a: () => target.stepYears(-1),
			f: () => target.stepYears(1),
			w: () => target.weekStart = target.weekStart === 1 ? 0 : 1,
			r: () => target.cursor = new Date(target.today)
		});
	}

	function kill(event, target) {
		return root.act(event, { [Config.procKillKey]: () => target.current && target.killRequested(target.current) });
	}

	function github(event, target) {
		return root.act(event, {
			escape: () => target.closeRequested(),
			r: () => target.refreshRequested()
		});
	}

	function notifications(event, target) {
		return root.act(event, {
			escape: () => target.closeRequested(),
			up: () => target.move(-1),
			down: () => target.move(1),
			right: () => target.open(),
			left: target.opened ? () => target.back() : undefined,
			[Config.notifyDismissKey]: () => target.dismiss(),
			[Config.notifyClearKey]: () => target.clearAll(),
			accept: () => target.accept()
		});
	}

	function mixer(event, target) {
		return root.act(event, {
			escape: () => target.closeRequested(),
			left: () => target.moveTarget(-1),
			right: () => target.moveTarget(1),
			up: () => target.nudgeVolume(Config.mixerStep),
			down: () => target.nudgeVolume(-Config.mixerStep),
			m: () => target.toggleMute(target.selectedNode),
			accept: () => target.sameNode(target.selectedNode, target.sink)
				? target.openPicker("output")
				: target.sameNode(target.selectedNode, target.source) ? target.openPicker("input") : null
		});
	}

	function picker(event, target) {
		return root.act(event, {
			escape: () => target.closeRequested(),
			up: () => target.pickerIndex = Math.max(0, target.pickerIndex - 1),
			down: () => target.pickerIndex = Util.clamp(target.pickerIndex + 1, 0, target.devices.length - 1),
			accept: () => target.makeDefault(target.picker, target.devices[target.pickerIndex])
		});
	}

	function switcher(event, target) {
		return root.act(event, {
			escape: () => target.close(),
			accept: () => target.activate(target.results[target.winIndex]),
			space: () => target.activate(target.results[target.winIndex]),
			left: () => target.stepWindows(-1),
			right: () => target.stepWindows(1),
			up: () => target.stepWindows(-target.windowColumns),
			down: () => target.stepWindows(target.windowColumns)
		});
	}
}
