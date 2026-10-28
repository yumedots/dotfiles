pragma Singleton

import QtQuick
import qs
import qs.services

Item {
	id: root

	visible: false

	readonly property var resolved: Yudae.icons.map || ({})
	property var asked: ({})

	function iconOf(appId, extra) {
		const names = Apps.iconNames([appId].concat(extra || []));

		for (let i = 0; i < names.length; i++) {
			const path = root.resolved[names[i]];

			if (path)
				return path;
		}

		root.ask(names);

		return "";
	}

	function iconOfPid(pid) {
		if (!pid)
			return "";

		const key = "pid:" + pid;
		const path = root.resolved[key];

		if (path !== undefined)
			return path;

		root.askPid(pid);

		return "";
	}

	function walkPid(pid) {
		root.iconOfPid(pid);
	}

	function ask(names) {
		const now = Date.now();
		const missing = [];

		for (let i = 0; i < names.length; i++) {
			const name = names[i];

			if (!name)
				continue;

			const at = root.asked[name];

			if (at !== undefined && (root.resolved[name] !== undefined || now - at < 2000))
				continue;

			root.asked[name] = now;
			missing.push(name);
		}

		if (missing.length > 0)
			Yudae.iconsWant(missing);
	}

	function askPid(pid) {
		const key = "pid:" + pid;
		const now = Date.now();
		const at = root.asked[key];

		if (at !== undefined && now - at < 2000)
			return;

		root.asked[key] = now;
		Yudae.iconsWantPid(pid);
	}
}
