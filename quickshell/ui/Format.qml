pragma Singleton

import QtQuick

QtObject {
	const objectPath = "/org/mpris/MediaPlayer2";
	const playerInterface = "org.mpris.MediaPlayer2.Player";
	const methods = { playPause: "PlayPause", next: "Next", previous: "Previous" };

	function hasContent(player) {
		if (!player)
			return false;

		if (player.isPlaying)
			return true;

		return String(player.trackTitle || "") !== "";
	}

	function pickPlayer(players) {
		const list = players || [];

		return list.filter(function (player) { return player.isPlaying; })[0] || list[0] || null;
	}

	function timeText(seconds) {
		const total = Math.max(0, Math.floor(Number(seconds) || 0));
		const minutes = Math.floor(total / 60);
		const rest = total % 60;

		if (minutes < 60)
			return minutes + ":" + (rest < 10 ? "0" : "") + rest;

		return Math.floor(minutes / 60) + ":" + (minutes % 60 < 10 ? "0" : "") + (minutes % 60) + ":" + (rest < 10 ? "0" : "") + rest;
	}

	function clock(player, position) {
		const length = player && player.length > 0 ? player.length : 0;
		const at = length > 0 ? Math.min(Math.max(Number(position) || 0, 0), length) : 0;

		return {
			known: length > 0,
			percent: length > 0 ? 100 * at / length : 0,
			elapsed: timeText(at),
			total: timeText(length)
		};
	}

	function command(players, action) {
		const player = pickPlayer(players);
		const method = methods[action];

		if (!player || !player.dbusName || !method)
			return [];

		return ["busctl", "--user", "call", player.dbusName, objectPath, playerInterface, method];
	}

	function daysInMonth(year, month) {
		return new Date(year, month + 1, 0).getDate();
	}

	function weekStartIndex(value) {
		const start = Math.round(value);

		return isFinite(start) && start >= 0 && start <= 6 ? start : 1;
	}

	function weekdayOffset(date, weekStart) {
		return (date.getDay() - weekStartIndex(weekStart) + 7) % 7;
	}

	function weekdayLabels(weekStart) {
		const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
		const start = weekStartIndex(weekStart);
		const out = [];

		for (let i = 0; i < 7; i++)
			out.push(names[(start + i) % 7]);

		return out;
	}

	function dateKey(date) {
		const month = String(date.getMonth() + 1).padStart(2, "0");
		const day = String(date.getDate()).padStart(2, "0");

		return date.getFullYear() + "-" + month + "-" + day;
	}

	function monthGrid(year, month, weekStart, todayKey, cursorKey, rows) {
		const height = rows > 0 ? Math.round(rows) : 6;
		const date = new Date(year, month, 1 - weekdayOffset(new Date(year, month, 1), weekStart));
		const today = String(todayKey || "");
		const cursor = String(cursorKey || "");
		const grid = [];

		for (let row = 0; row < height; row++) {
			const days = [];

			for (let d = 0; d < 7; d++) {
				const key = dateKey(date);

				days.push({
					key: key,
					day: date.getDate(),
					inMonth: date.getMonth() === month && date.getFullYear() === year,
					weekend: date.getDay() === 0 || date.getDay() === 6,
					today: key === today,
					cursor: key === cursor
				});

				date.setDate(date.getDate() + 1);
			}

			grid.push(days);
		}

		return grid;
	}

	function dayProgress(date) {
		const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());

		return Math.min(Math.max((date.getTime() - start.getTime()) / 86400000, 0), 1);
	}

	function monthProgress(date) {
		return (date.getDate() - 1 + dayProgress(date)) / daysInMonth(date.getFullYear(), date.getMonth());
	}

	function daysInYear(year) {
		return daysInMonth(year, 1) === 29 ? 366 : 365;
	}

	function yearProgress(date) {
		const day = Math.round((Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) - Date.UTC(date.getFullYear(), 0, 1)) / 86400000) + 1;

		return (day - 1 + dayProgress(date)) / daysInYear(date.getFullYear());
	}

	function lifeProgress(birthYear, expectancy, year) {
		const born = Math.round(birthYear);
		const span = Math.round(expectancy);

		if (!isFinite(born) || !isFinite(span) || born <= 0 || span <= 0 || year < born)
			return 0;

		return Math.min((year - born) / span, 1);
	}

	function progressPercent(value) {
		return Math.round(Math.min(Math.max(value, 0), 1) * 100);
	}

	function shiftDays(date, days) {
		const next = new Date(date.getTime());

		next.setDate(next.getDate() + days);

		return next;
	}

	function shiftMonths(date, months) {
		const next = new Date(date.getTime());
		const day = next.getDate();

		next.setDate(1);
		next.setMonth(next.getMonth() + months);
		next.setDate(Math.min(day, daysInMonth(next.getFullYear(), next.getMonth())));

		return next;
	}

	function meters(today, birthYear, expectancy, icons) {
		const out = [
			{ icon: icons[0], label: "DAY", pct: progressPercent(dayProgress(today)) },
			{ icon: icons[1], label: "MONTH", pct: progressPercent(monthProgress(today)) },
			{ icon: icons[2], label: "YEAR", pct: progressPercent(yearProgress(today)) }
		];

		if (birthYear > 0)
			out.push({ icon: icons[3], label: "LIFE", pct: progressPercent(lifeProgress(birthYear, expectancy, today.getFullYear())) });

		return out;
	}

	function shiftYears(date, years) {
		const next = new Date(date.getTime());
		const day = next.getDate();

		next.setDate(1);
		next.setFullYear(next.getFullYear() + years);
		next.setDate(Math.min(day, daysInMonth(next.getFullYear(), next.getMonth())));

		return next;
	}
	function weatherCodeInfo(code, table, fallback) {
		const row = (table || {})[code];

		if (row)
			return row;

		return { name: "", glyph: fallback || "" };
	}

	function splitTemp(temp) {
		const match = /^([+-]?\d+(?:\.\d+)?)\s*(.*)$/.exec(String(temp || "").trim());

		if (!match)
			return { value: String(temp || "").trim(), unit: "" };

		return { value: match[1], unit: match[2] };
	}
}
