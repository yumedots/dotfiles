.pragma library

function cleanName(name) {
	const value = String(name === undefined || name === null ? "" : name).trim();

	if (value.endsWith(".desktop"))
		return value.slice(0, value.length - 8);

	return value;
}

function iconNames(names) {
	const out = [];

	(names || []).forEach(function (name) {
		const value = cleanName(name);

		if (!value)
			return;

		const seen = out.some(function (other) {
			return other.toLowerCase() === value.toLowerCase();
		});

		if (!seen)
			out.push(value);
	});

	return out;
}

function detectPrefix(query, marks) {
	const text = String(query === undefined || query === null ? "" : query);
	const modes = Object.keys(marks || {});

	for (let i = 0; i < modes.length; i++) {
		const mark = marks[modes[i]];

		if (mark && text.indexOf(mark) === 0)
			return { mode: modes[i], mark: mark, text: text.substring(mark.length) };
	}

	return { mode: "", mark: "", text: text };
}

function fuzzyScore(text, query) {
	const target = String(text === undefined || text === null ? "" : text).toLowerCase();
	const needle = String(query === undefined || query === null ? "" : query).toLowerCase();

	if (!needle)
		return 0;
	if (target === needle)
		return 1000;

	let score = 0;
	let at = 0;
	let streak = 0;

	for (let i = 0; i < needle.length; i++) {
		const found = target.indexOf(needle[i], at);

		if (found < 0)
			return null;

		streak = found === at ? streak + 1 : 0;
		score += 10 + streak * 6;

		if (found === 0)
			score += 30;
		else if (" -_/.".indexOf(target[found - 1]) >= 0)
			score += 20;

		at = found + 1;
	}

	return score - Math.max(0, target.length - needle.length) * 0.2;
}

function entryScore(entry, query) {
	const names = [entry.name].concat(entry.keywords || []);
	let best = null;

	for (let i = 0; i < names.length; i++) {
		const score = fuzzyScore(names[i], query);

		if (score !== null && (best === null || score > best))
			best = score;
	}

	return best;
}

function rankEntries(entries, query, pins, usage) {
	const kept = [];

	(entries || []).forEach(function (entry) {
		const score = entryScore(entry, query);

		if (score === null)
			return;

		const used = (usage || {})[entry.id] || { count: 0, last: 0 };

		kept.push({ entry: entry, score: score, pin: (pins || []).indexOf(entry.id), count: used.count, last: used.last, power: entry.kind === "action" ? 1 : 0 });
	});

	kept.sort(function (a, b) {
		if (a.power !== b.power)
			return a.power - b.power;

		const pinnedA = a.pin < 0 ? 1 : 0;
		const pinnedB = b.pin < 0 ? 1 : 0;

		if (pinnedA !== pinnedB)
			return pinnedA - pinnedB;
		if (a.pin !== b.pin)
			return a.pin - b.pin;
		if (a.score !== b.score)
			return b.score - a.score;
		if (a.count !== b.count)
			return b.count - a.count;
		if (a.last !== b.last)
			return b.last - a.last;

		return String(a.entry.name).localeCompare(String(b.entry.name));
	});

	return kept.map(function (item) { return item.entry; });
}

function home(entries, pins) {
	return (entries || []).filter(function (entry) {
		return entry.kind !== "app" || (pins || []).indexOf(entry.id) >= 0;
	});
}

