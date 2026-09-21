.pragma library

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
