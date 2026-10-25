pragma Singleton

import QtQuick
import Quickshell
import qs

// The GitHub contribution grid, read from yudaemond. The daemon finds the
// login, fetches the page and parses the days; this only lays the days out.
QtObject {
	id: root

	readonly property var source: Yudae.github

	readonly property string login: root.source.login || ""
	readonly property int total: root.source.total || 0
	readonly property real fetched: root.source.fetched || 0
	readonly property string status: root.source.status || ""
	readonly property bool loading: false
	readonly property var days: root.source.days || []

	readonly property string dayStamp: root.dayKey(new Date())
	readonly property var grid: Contrib.contribGrid(root.days, Config.contribWeeks, root.dayStamp)
	readonly property var today: root.dayOn(new Date())
	readonly property int todayCount: root.today ? root.today.count : 0
	readonly property int todayLevel: root.today ? root.today.level : 0
	readonly property var last: root.days.length > 0 ? root.days[root.days.length - 1] : null

	function dayKey(date) {
		const pad = function (value) {
			return value < 10 ? "0" + value : String(value);
		};

		return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
	}

	function dayOn(date) {
		const key = root.dayKey(date);

		for (let i = 0; i < root.days.length; i++)
			if (root.days[i].date === key)
				return root.days[i];

		return null;
	}

	function refresh(force) {
		if (force)
			Yudae.send({ refresh: true });
	}
}
