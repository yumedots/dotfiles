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
	readonly property var grid: contribGrid(root.days, Config.contribWeeks, root.dayStamp)
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

	function parseContributions(html) {
		const text = String(html || "");
		const cells = text.split(/data-date="/).slice(1);
		const days = [];

		cells.forEach(function (chunk) {
			const date = chunk.substring(0, chunk.indexOf("\""));
			const level = /data-level="([0-9]+)"/.exec(chunk);
			const tip = /<tool-tip[^>]*>([\s\S]*?)<\/tool-tip>/.exec(chunk);
			const count = tip ? /([0-9]+)\s+contribution/.exec(tip[1]) : null;

			if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(date))
				return;

			days.push({
				date: date,
				level: level ? parseInt(level[1], 10) : 0,
				count: count ? parseInt(count[1], 10) : 0
			});
		});

		const total = /([0-9,]+)\s*\n?\s*contributions?\s*\n?\s*in the last year/.exec(text);

		return {
			days: days,
			total: total ? parseInt(total[1].replace(/,/g, ""), 10) : 0
		};
	}

	function weekIndex(date) {
		const days = Math.round(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000);

		return Math.floor((days - 3) / 7);
	}

	function contribGrid(days, weeks, today) {
		const cols = Math.max(1, Math.round(weeks || 13));
		const cells = new Array(cols * 7).fill(null);
		const limit = typeof today === "string" ? today : "";
		const list = (days || []).filter(function (day) {
			return day && (!limit || day.date <= limit);
		}).sort(function (a, b) {
			return a.date < b.date ? -1 : 1;
		});

		const anchor = limit !== "" ? limit : (list.length > 0 ? list[list.length - 1].date : "");

		if (anchor === "")
			return cells;

		const lastWeek = weekIndex(new Date(anchor + "T00:00:00"));

		list.forEach(function (day) {
			const date = new Date(day.date + "T00:00:00");
			const col = cols - 1 - (lastWeek - weekIndex(date));

			if (col < 0)
				return;

			cells[date.getDay() * cols + col] = day;
		});

		return cells;
	}
}
