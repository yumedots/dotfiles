//@ pragma IconTheme breeze
import QtQuick
import qs
import Quickshell
import Quickshell.Io
import "launcher"

Root {
	role: "launcher"

	FileView {
		id: wake
		path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-launcher-wake"
		preload: true
		blockLoading: true
		printErrors: false
	}

	Component.onCompleted: {
		const action = (wake.text() || "").trim();

		if (action === "launcher")
			launcher();
		else if (action === "windows")
			windowSwitcher();
		else if (action === "clipboard")
			clipboard();
		else if (action === "powerMenu")
			powerMenu();

		if (action)
			Quickshell.execDetached(["rm", wake.path]);
	}
}
