pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import "lock"
import "greeter"
import "greeter/Local.js" as Local

ShellRoot {
	id: greeterRoot

	readonly property bool preview: Quickshell.env("QS_GREETER_PREVIEW") === "1"
	property string saver: Local.saver

	readonly property var powerActions: [
		{ name: "Shut down", verb: "poweroff", glyph: "\uf011" },
		{ name: "Reboot", verb: "reboot", glyph: "\uead2" },
		{ name: "Suspend", verb: "suspend", glyph: "\udb81\udcb2" }
	]

	function runPower(action) {
		Quickshell.execDetached(["sudo", "-n", "/usr/bin/systemctl", action.verb]);
	}

	Session {
		id: auth

		preview: greeterRoot.preview
	}

	Variants {
		id: screens

		model: Quickshell.screens

		Stage {
			source: auth
			wallpaper: Local.wallpaper
			saver: greeterRoot.saver
			scrim: 0
			account: Local.user
			power: true
			actions: greeterRoot.powerActions

			onActionPicked: function (action) {
				greeterRoot.runPower(action);
			}
		}
	}

	IpcHandler {
		target: "greeter"

		function screensaver(name: string) {
			greeterRoot.saver = name;
		}

		function power() {
			for (let i = 0; i < screens.instances.length; i++)
				screens.instances[i].menuOpen = true;
		}
	}
}
