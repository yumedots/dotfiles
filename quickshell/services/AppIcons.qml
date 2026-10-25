pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Item {
	id: root

	property var entries: Yudae.appsEntries
	property var icons: ({})

	// The icon listing as it was read, so the same text is not parsed twice.
	property string iconText: ""
	property var resolved: ({})
	property var pidIcons: ({})
	property var pidWalked: ({})
	property var pidQueue: []
	property int pidWalking: 0
	readonly property string cachePath: Quickshell.shellDir + "/cache/icons.txt"

	function entryOf(appId) {
		return Apps.lookupApp(root.entries, appId);
	}

	// The icon of a name, looked up as a desktop entry first so the app's own
	// icon wins over a file that happens to share the name.
	function iconFor(name) {
		const value = Apps.cleanName(name);

		if (!value)
			return "";

		const entry = root.entryOf(value);

		if (entry && entry.icon) {
			const path = root.iconSource(entry.icon);

			if (path !== "")
				return path;
		}

		return root.iconSource(value);
	}

	function iconOf(appId, extra) {
		if (appId && root.resolved[appId])
			return root.resolved[appId];

		const names = Apps.iconNames([appId].concat(extra || []));

		for (let i = 0; i < names.length; i++) {
			const path = root.iconFor(names[i]);

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
		const file = Apps.iconLookup(root.icons, name);

		if (file)
			return "file://" + file;
		if (Quickshell.hasThemeIcon(name))
			return Quickshell.iconPath(name, true);

		return "";
	}

	// The icon of the app a notification came from. A command run in a
	// terminal belongs to that terminal, so the app is the closest ancestor
	// of the sender that has an icon of its own.
	function iconOfPid(pid) {
		if (!pid)
			return "";

		return root.pidIcons[pid] || "";
	}

	function walkPid(pid) {
		if (!pid || root.pidWalked[pid])
			return;

		root.pidWalked = Object.assign({}, root.pidWalked, { [pid]: true });
		root.pidQueue = root.pidQueue.concat([pid]);
		root.walkNext();
	}

	function walkNext() {
		if (pidWalk.running || root.pidQueue.length === 0)
			return;

		const pid = root.pidQueue[0];

		root.pidWalking = pid;
		pidWalk.command = ["sh", "-c", "p=" + pid + "; i=0; while [ $p -gt 1 ] && [ $i -lt 8 ]; do n=$(cat /proc/$p/comm 2>/dev/null) || break; echo $n; p=$(awk '{print $4}' /proc/$p/stat 2>/dev/null); i=$((i+1)); done"];
		pidWalk.running = true;
	}

	// The icon of an app does not change when another app is added, so the
	// paths that are already resolved are kept. Wiping them made the next
	// search resolve every icon again, which is slow.

	Component.onCompleted: iconScan.running = true

	Request {
		id: iconScan

		command: ["sh", "-c", "for dir in \"$HOME/.local/share\" $(echo \"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\" | tr ':' ' '); do find \"$dir/icons/breeze\" \"$dir/icons/hicolor\" \"$dir/pixmaps\" -mindepth 1 -maxdepth 3 \\( -type f -o -type l \\) \\( -name '*.png' -o -name '*.svg' -o -name '*.xpm' \\) 2>/dev/null; done | tee " + Shell.shellQuote(root.cachePath)]

		onDone: function (text) {
			// The listing is read from the cache file as well, so the same
			// text is parsed once and not twice.
			if (text === root.iconText)
				return;

			root.iconText = text;
			root.icons = Apps.iconFiles(text);
		}
	}

	Request {
		id: pidWalk

		onDone: function (text) {
			const names = text.split("\n").map(function (line) {
				return line.trim();
			}).filter(function (line) {
				return line !== "";
			});

			let path = "";

			for (let i = 0; i < names.length; i++) {
				path = root.iconFor(names[i]);

				if (path !== "")
					break;
			}

			root.pidIcons = Object.assign({}, root.pidIcons, { [root.pidWalking]: path });
			root.pidQueue = root.pidQueue.slice(1);
			root.walkNext();
		}
	}

	FileView {
		id: iconCache

		path: root.cachePath
		preload: true
		printErrors: false

		onLoaded: {
			const text = iconCache.text();

			if (text === root.iconText)
				return;

			root.iconText = text;
			root.icons = Apps.iconFiles(text);
		}
	}
}
