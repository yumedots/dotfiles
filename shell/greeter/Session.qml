import QtQuick
import Quickshell
import Quickshell.Services.Greetd
import qs
import qs.services
import "Local.js" as Local

Item {
	id: root

	signal unlocked()

	property string password: ""
	property int filled: 0
	property string mode: "locked"
	property string message: ""
	property bool preview: false
	property bool cooling: false
	property string pending: ""
	property bool launching: false

	readonly property string user: Local.user

	function type(text) {
		if (text === "" || root.mode === "checking" || root.mode === "open" || root.password.length >= 256)
			return;

		root.password += text;
		root.filled = root.password.length;
		root.message = "";
		root.mode = "locked";
	}

	function back() {
		if (root.mode === "checking" || root.mode === "open" || root.password.length === 0)
			return;

		root.password = root.password.slice(0, -1);
		root.filled = root.password.length;
	}

	function clear() {
		if (root.mode === "checking" || root.mode === "open")
			return;

		root.password = "";
		root.filled = 0;
		root.message = "";
		root.mode = "locked";
	}

	function dismiss() {
		if (root.preview)
			Qt.quit();
		else
			root.clear();
	}

	function submit() {
		if (root.password === "" || root.mode === "checking" || root.mode === "open" || root.cooling)
			return;

		root.mode = "checking";
		root.pending = root.password;
		root.password = "";

		if (root.preview) {
			open();
			return;
		}

		guard.restart();
		Greetd.createSession(root.user);
	}

	function open() {
		if (root.mode === "open")
			return;

		root.mode = "open";
		root.pending = "";
		root.unlocked();
		Qt.callLater(root.launch);
	}

	function launch() {
		if (root.launching)
			return;

		root.launching = true;

		if (root.preview) {
			Qt.quit();
			return;
		}

		Greetd.launch([Local.session], ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland", "XDG_SESSION_DESKTOP=Hyprland"], true);
	}

	function fail(text) {
		root.password = "";
		root.filled = 0;
		root.mode = "wrong";
		root.message = text === "" ? Config.lockWrongText : text;
		root.cooling = true;
		relax.restart();
	}

	Connections {
		target: Greetd

		function onAuthMessage(message, error, responseRequired, echo) {
			if (responseRequired) {
				const value = root.pending;

				root.pending = "";
				root.mode = "checking";
				guard.stop();
				Greetd.respond(value);
			}
		}

		function onAuthFailure(message) {
			guard.stop();
			root.fail(Config.lockWrongText);
		}

		function onReadyToLaunch() {
			guard.stop();
			root.open();
		}

		function onError(error) {
			guard.stop();

			if (root.mode === "checking")
				root.fail(Config.greeterUnavailableText);
		}
	}

	Timer {
		id: guard

		interval: 8000
		onTriggered: root.fail(Config.greeterUnavailableText)
	}

	Timer {
		id: relax

		interval: Math.max(0, Config.lockCooldownMs)
		onTriggered: {
			root.message = "";
			root.cooling = false;

			if (root.mode === "wrong")
				root.mode = "locked";
		}
	}
}
