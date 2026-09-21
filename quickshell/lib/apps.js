.pragma library

function commandWord(title) {
	const word = (title || "").split(" ")[0].replace(/:$/, "");

	if (!word || word.indexOf("/") >= 0 || word.indexOf("~") >= 0)
		return "";

	return word.toLowerCase();
}

function terminalAppId(cls, title, terminals) {
	if (terminals.indexOf(String(cls).toLowerCase()) < 0)
		return cls;

	return commandWord(title);
}

function iconRank(path) {
	if (path.indexOf("/scalable/") >= 0)
		return Infinity;

	const match = /(\d+)x\d+/.exec(path);

	return match ? Number(match[1]) : 0;
}

function iconFiles(text) {
	const files = {};
	const ranks = {};

	String(text === undefined || text === null ? "" : text).split("\n").forEach(function (path) {
		if (path === "")
			return;

		const name = path.substring(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "");
		const rank = iconRank(path);

		if (ranks[name] === undefined || rank > ranks[name]) {
			ranks[name] = rank;
			files[name] = path;
		}
	});

	return files;
}

function cleanExec(value) {
	return String(value === undefined || value === null ? "" : value)
		.replace(/%[uUfFiIcCkK]/g, "")
		.replace(/%%/g, "%")
		.replace(/\s+/g, " ")
		.trim();
}

function launchCommand(entry, appId, terminal) {
	const line = entry && entry.execLine ? entry.execLine : (entry && entry.exec ? entry.exec : appId);

	if (entry && entry.terminal)
		return [terminal, "-e", "sh", "-c", line];

	return ["sh", "-c", line];
}

function terminalName(text) {
	const source = String(text === undefined || text === null ? "" : text);
	const match = /(?:^|\n)[ \t]*(?:local[ \t]+)?\$?terminal[ \t]*=[ \t]*["']?([^"'\s]+)["']?/.exec(source);

	return match ? match[1] : "";
}

function togglePin(pins, appId) {
	const kept = pins.filter(function (id) { return id.toLowerCase() !== appId.toLowerCase(); });

	if (kept.length === pins.length)
		kept.push(appId);

	return kept;
}

function pinnedFromText(text) {
	return (text || "").split("\n").map(function (line) { return line.trim(); }).filter(function (line) { return line !== ""; });
}

function desktopEntries(apps) {
	const entries = {};

	(apps || []).forEach(function (app) {
		const command = app.command && app.command.length ? String(app.command[0]) : "";

		entries[app.id] = {
			id: app.id,
			name: app.name,
			icon: app.icon,
			wmclass: app.startupClass,
			exec: command.substring(command.lastIndexOf("/") + 1),
			execLine: cleanExec(app.execString),
			terminal: app.runInTerminal
		};
	});

	return entries;
}

function lookupApp(entries, name) {
	if (!name)
		return null;

	const wanted = name.toLowerCase();
	const usable = function (entry) {
		return entry && entry.icon;
	};

	if (usable(entries[name]))
		return entries[name];

	const keys = Object.keys(entries);
	const fields = ["id", "wmclass", "exec", "name"];

	for (let i = 0; i < fields.length; i++) {
		for (let j = 0; j < keys.length; j++) {
			const entry = entries[keys[j]];

			if (usable(entry) && entry[fields[i]] && entry[fields[i]].toLowerCase() === wanted)
				return entry;
		}
	}

	return null;
}

function windowAppCandidates(toplevel, terminals) {
	const info = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : {};
	const className = info.class || "";

	return { className: className, word: terminalAppId(className, info.title || "", terminals) };
}

function appEntries(entries, ignore) {
	const out = [];
	const skip = ignore || [];

	Object.keys(entries || {}).forEach(function (id) {
		const entry = entries[id];

		if (!entry || !entry.name || !entry.exec || skip.indexOf(id) >= 0)
			return;

		out.push({
			id: "app:" + id,
			kind: "app",
			appId: id,
			name: entry.name,
			keywords: [id].concat(entry.exec ? [entry.exec] : []),
			exec: entry.exec,
			execLine: entry.execLine,
			terminal: entry.terminal
		});
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

		kept.push({ entry: entry, score: score, pin: (pins || []).indexOf(entry.id), count: used.count, last: used.last });
	});

	kept.sort(function (a, b) {
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

function parseUsage(text) {
	const usage = {};

	String(text || "").split("\n").forEach(function (line) {
		const parts = line.split("\t");

		if (parts.length < 2 || !parts[0])
			return;

		const count = parseInt(parts[1], 10);
		const last = parts.length > 2 ? parseInt(parts[2], 10) : 0;

		usage[parts[0]] = { count: isNaN(count) ? 0 : count, last: isNaN(last) ? 0 : last };
	});

	return usage;
}

function formatUsage(usage, max) {
	const kept = Object.keys(usage || {}).map(function (id) {
		return { id: id, count: usage[id].count, last: usage[id].last };
	});

	const capped = max > 0 && kept.length > max
		? kept.sort(function (a, b) { return (b.last - a.last) || (b.count - a.count); }).slice(0, max)
		: kept;

	return capped.sort(function (a, b) { return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0); }).map(function (entry) {
		return entry.id + "\t" + entry.count + "\t" + entry.last;
	}).join("\n");
}

function bumpUsage(usage, id, now) {
	const next = {};

	Object.keys(usage || {}).forEach(function (key) {
		next[key] = { count: usage[key].count, last: usage[key].last };
	});

	next[id] = { count: (next[id] ? next[id].count : 0) + 1, last: now };

	return next;
}

function commandEntries(items) {
	return (items || []).map(function (item) {
		return {
			id: "cmd:" + item.name,
			kind: "command",
			name: item.name,
			keywords: item.keywords || [],
			command: item.command
		};
	});
}

function actionEntries(items) {
	return (items || []).map(function (item) {
		return {
			id: "act:" + item.name,
			kind: "action",
			name: item.name,
			keywords: ["power", "session"],
			command: item.command,
			glyph: item.glyph
		};
	});
}

function clipEntries(list) {
	return (list || []).map(function (entry) {
		return { id: "clip:" + entry.id, kind: "clip", name: entry.text, keywords: [], clipId: entry.id };
	});
}

function fileEntries(paths) {
	return (paths || []).map(function (path) {
		return { id: "file:" + path, kind: "file", name: path, keywords: [], path: path };
	});
}

function rememberable(entry) {
	return Boolean(entry) && entry.kind !== "calc" && entry.kind !== "file" && entry.kind !== "clip" && entry.kind !== "window";
}

function results(mode, search, state) {
	if (mode === "files")
		return state.files;
	if (mode === "clipboard")
		return state.clips;
	if (mode === "windows")
		return search === "" ? state.windows : rankEntries(state.windows, search, [], {});

	const ranked = rankEntries(state.entries, search, state.pins, state.usage);

	return state.calc === null ? ranked : [state.calc].concat(ranked);
}
