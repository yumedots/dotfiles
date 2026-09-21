import QtQuick
import qs.ui
import qs

QtObject {
	id: root

	function assert(condition, message) {
		if (!condition)
			throw new Error("input check failed: " + message);
	}

	function key(text, code) {
		return { text: text, key: code };
	}

	Component.onCompleted: {
		const j = root.key("j", 0);
		const k = root.key("k", 0);
		const h = root.key("h", 0);
		const l = root.key("l", 0);
		const down = root.key("", Qt.Key_Down);
		const up = root.key("", Qt.Key_Up);
		const left = root.key("", Qt.Key_Left);
		const right = root.key("", Qt.Key_Right);
		const escape = root.key("", Qt.Key_Escape);
		const other = root.key("q", Qt.Key_Q);

		root.assert(Input.direction(j) === "down" && Input.direction(down) === "down", "down");
		root.assert(Input.direction(k) === "up" && Input.direction(up) === "up", "up");
		root.assert(Input.direction(h) === "left" && Input.direction(left) === "left", "left");
		root.assert(Input.direction(l) === "right" && Input.direction(right) === "right", "right");
		root.assert(Input.direction(other) === "" && Input.direction(root.key("j", Qt.Key_J)) === "down", "non movement keys stand aside");

		root.assert(Input.delta(j, 1, 5) === 1 && Input.delta(k, 1, 5) === -1, "rows move one step");
		root.assert(Input.delta(l, 1, 5) === 5 && Input.delta(h, 1, 5) === -5, "page keys move a whole page");
		root.assert(Input.delta(down, 7, 1) === 7 && Input.delta(up, 7, 1) === -7, "arrows reuse the step");
		root.assert(Input.delta(other, 1, 5) === 0, "nothing matches returns zero");

		root.assert(Input.arrow(down, 1, 5) === 1 && Input.arrow(up, 1, 5) === -1, "arrows only");
		root.assert(Input.arrow(j, 1, 5) === 0 && Input.arrow(l, 1, 5) === 0, "letters are not swallowed while typing");

		root.assert(Input.name(escape) === "escape" && Input.name(root.key("", Qt.Key_Return)) === "accept" && Input.name(j) === "down" && Input.name(other) === "q", "keys get one name");
		root.assert(Input.cancel(escape) && !Input.cancel(j), "escape cancels");
		root.assert(Input.accept(root.key("", Qt.Key_Return)) && Input.accept(root.key("", Qt.Key_Enter)) && !Input.accept(j), "return and enter accept");
		root.assert(Input.hint(root.key("f", Qt.Key_F)) && !Input.hint(root.key("g", Qt.Key_G)), "the hint key comes from config");
		root.assert(Input.pin({ text: "", key: Qt.Key_P, modifiers: Qt.ControlModifier }) && !Input.pin(root.key("", Qt.Key_P)), "ctrl p pins");

		let seen = "";
		const stub = {
			opened: false,
			picker: "output",
			pickerIndex: 0,
			devices: [{}, {}],
			weekStart: 1,
			today: new Date(),
			cursor: null,
			selectedNode: "sink",
			sink: "sink",
			source: "source",
			winIndex: 0,
			results: ["window"],
			windowColumns: 3,
			closeRequested: () => seen = "close",
			move: (n) => seen = "move" + n,
			open: () => seen = "open",
			back: () => seen = "back",
			dismiss: () => seen = "dismiss",
			clearAll: () => seen = "clear",
			accept: () => seen = "accept",
			step: (n) => seen = "step" + n,
			stepMonths: (n) => seen = "months" + n,
			stepYears: (n) => seen = "years" + n,
			moveTarget: (n) => seen = "target" + n,
			nudgeVolume: (n) => seen = "volume" + n,
			toggleMute: () => seen = "mute",
			openPicker: (dir) => seen = "picker:" + dir,
			makeDefault: () => seen = "default",
			activate: () => seen = "activate",
			stepWindows: (n) => seen = "window" + n,
			refreshRequested: () => seen = "refresh",
			current: "process",
			killRequested: () => seen = "kill"
		};

		seen = "";
		Input.calendar(root.key("l", 0), stub);
		root.assert(seen === "step1", "calendar moves a day");

		seen = "";
		Input.calendar(root.key("k", 0), stub);
		root.assert(seen === "step-7", "calendar moves a week");

		seen = "";
		Input.calendar(root.key("s", 0), stub);
		root.assert(seen === "months-1", "calendar steps a month");

		seen = "";
		Input.calendar(escape, stub);
		root.assert(seen === "close" && stub.cursor === null, "calendar closes on escape");

		seen = "";
		Input.notifications(root.key(Config.notifyDismissKey, 0), stub);
		root.assert(seen === "dismiss", "the notification dismiss key comes from config");

		seen = "";
		Input.notifications(root.key(Config.notifyClearKey, 0), stub);
		root.assert(seen === "clear", "the notification clear key comes from config");

		seen = "";
		Input.notifications(down, stub);
		root.assert(seen === "move1", "notifications move down");

		seen = "";
		Input.notifications(left, stub);
		root.assert(seen === "", "back is not bound while a notification is closed");

		stub.opened = true;
		Input.notifications(left, stub);
		root.assert(seen === "back", "back walks out of an open notification");
		stub.opened = false;

		seen = "";
		Input.mixer(down, stub);
		root.assert(seen === "volume" + -Config.mixerStep, "mixer down lowers the volume");

		seen = "";
		Input.mixer(root.key("m", 0), stub);
		root.assert(seen === "mute", "mixer mutes");

		seen = "";
		Input.mixer(root.key("", Qt.Key_Return), stub);
		root.assert(seen === "picker:output", "the mixer opens the sink picker");

		seen = "";
		Input.picker(down, stub);
		root.assert(seen === "" && stub.pickerIndex === 1, "the picker moves its highlight");

		seen = "";
		Input.switcher(root.key("", Qt.Key_Space), stub);
		root.assert(seen === "activate", "space activates in the window switcher");

		seen = "";
		Input.github(escape, stub);
		root.assert(seen === "close", "the github grid closes on escape");

		seen = "";
		Input.github(root.key("r", 0), stub);
		root.assert(seen === "refresh", "r refreshes the github grid");

		seen = "";
		Input.kill(root.key(Config.procKillKey, 0), stub);
		root.assert(seen === "kill", "the process kill key comes from config");

		seen = "";
		Input.switcher(down, stub);
		root.assert(seen === "window3", "the switcher moves a row");

		console.log("input check ok");
		Qt.quit();
	}
}
