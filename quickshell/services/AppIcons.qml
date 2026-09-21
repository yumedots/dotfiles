pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Item {
	id: root

	property var entries: Apps.desktopEntries(DesktopEntries.applications.values)
	property var icons: ({})
	property var resolved: ({})

	function entryOf(appId) {
		return Apps.lookupApp(root.entries, appId);
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

			const path = root.iconSource(String(candidates[i]));

			if (path === "")
				continue;

			if (appId)
				root.resolved[appId] = path;

			return path;
		}

		return "";
	}

	function iconSource(name) {
		if (name.indexOf("/") >= 0)
			return "file://" + name;
		if (Quickshell.hasThemeIcon(name))
			return Quickshell.iconPath(name, true);

		return root.icons[name] ? "file://" + root.icons[name] : "";
	}

	onEntriesChanged: {
		root.resolved = ({});
		iconScan.running = true;
	}

	Component.onCompleted: iconScan.running = true

	Process {
		id: iconScan

		command: ["sh", "-c", "for dir in \"$HOME/.local/share\" $(echo \"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\" | tr ':' ' '); do find \"$dir/icons/hicolor\" \"$dir/pixmaps\" -mindepth 1 -maxdepth 3 \\( -type f -o -type l \\) \\( -name '*.png' -o -name '*.svg' -o -name '*.xpm' \\) 2>/dev/null; done"]

		stdout: StdioCollector {
			onStreamFinished: root.icons = Apps.iconFiles(text)
		}
	}
}
