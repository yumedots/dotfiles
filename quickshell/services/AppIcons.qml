pragma Singleton

import QtQuick
import qs
import qs.services

Item {
	id: root

	visible: false

	readonly property var entries: Yudae.appsEntries
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

		Yudae.iconsWantPid(pid);

		return "";
	}

	function walkPid(pid) {
		root.iconOfPid(pid);
	}

	function ask(names) {
		const missing = [];

		for (let i = 0; i < names.length; i++) {
			const name = names[i];

			if (name && root.asked[name] === undefined) {
				root.asked[name] = true;
				missing.push(name);
			}
		}

		if (missing.length > 0)
			Yudae.iconsWant(missing);
	}
}
