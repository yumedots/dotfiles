pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Item {
	id: root

	property var entries: ({})
	property var resolved: ({})

	function entryOf(appId) {
		return Helpers.lookupApp(root.entries, appId);
	}

	function iconOf(appId, extra) {
		if (appId && root.resolved[appId])
			return root.resolved[appId];

		const fallbacks = extra || [];

		if (!appId && !fallbacks.length)
			return "";

		const entry = root.entryOf(appId);
		const candidates = [entry ? entry.icon : ""].concat(fallbacks).concat([appId, Config.fallbackIcon]);

		for (let i = 0; i < candidates.length; i++) {
			if (!candidates[i])
				continue;

			const named = String(candidates[i]);
			const path = named.indexOf("/") >= 0 ? named : (Quickshell.hasThemeIcon(named) ? Quickshell.iconPath(named, true) : "");

			if (path === "")
				continue;

			if (appId)
				root.resolved[appId] = path;

			return path;
		}

		return "";
	}

	function reload() {
		root.entries = ({});
		root.resolved = ({});
		desktopFiles.running = true;
	}

	onEntriesChanged: root.resolved = ({})

	Component.onCompleted: root.reload()

	Process {
		id: desktopFiles

		command: ["sh", "-c", "for dir in \"$HOME/.local/share\" $(echo \"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\" | tr ':' ' '); do grep -H -E '^(Name|Icon|StartupWMClass|Exec|NoDisplay|Hidden|Terminal)=' \"$dir/applications\"/*.desktop 2>/dev/null; done"]

		stdout: StdioCollector {
			onStreamFinished: root.entries = Helpers.parseDesktopEntries(text)
		}
	}
}
