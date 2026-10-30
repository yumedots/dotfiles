import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs
import qs.services

Item {
	id: root

	signal unlocked()

	property string password: ""
	property int filled: 0
	property string mode: "locked"
	property string message: ""
	property bool preview: false
	property bool cooling: false

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
			root.unlocked();
		else
			root.clear();
	}

	function submit() {
		if (root.password === "" || root.mode === "checking" || root.mode === "open" || root.cooling)
			return;

		root.mode = "checking";

		if (!pam.start())
			root.fail(Config.lockPamError);
	}

	function open() {
		root.password = "";
		root.mode = "open";
		grant.restart();
	}

	function fail(text) {
		root.password = "";
		root.filled = 0;
		root.mode = "wrong";
		root.message = text === "" ? Config.lockWrongText : text;
		root.cooling = true;
		relax.restart();
	}

	PamContext {
		id: pam

		config: Config.lockPamService
		configDirectory: Qt.resolvedUrl("pam.d")

		onResponseRequiredChanged: {
			if (!pam.responseRequired)
				return;

			const value = root.password;

			root.password = "";
			pam.respond(value);
		}

		onCompleted: function (result) {
			pam.active = false;

			if (result === PamResult.Success)
				root.open();
			else if (root.mode !== "wrong")
				root.fail(Config.lockWrongText);
		}

		onError: function (error) {
			pam.active = false;
			root.fail(PamError.toString(error));
		}
	}

	Timer {
		id: grant

		interval: 1300
		onTriggered: root.unlocked()
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
