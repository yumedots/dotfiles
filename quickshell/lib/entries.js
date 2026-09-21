.pragma library

function modeMarks(modes) {
	const marks = {};

	(modes || []).forEach(function (mode) {
		marks[mode.mode] = mode.mark;
	});

	return marks;
}

function modeInfo(mode, config) {
	if (mode.indexOf("group:") === 0) {
		const groups = config.launcherGroups || [];
		const id = mode.substring(6);

		for (let i = 0; i < groups.length; i++) {
			if (groups[i].id === id)
				return groups[i];
		}

		return null;
	}

	const modes = config.launcherModes || [];

	for (let j = 0; j < modes.length; j++) {
		if (modes[j].mode === mode)
			return modes[j];
	}

	return null;
}

function markOf(mode, config) {
	const info = modeInfo(mode, config);

	return info && info.mark ? info.mark : "";
}

function modeEntries(modes) {
	return (modes || []).map(function (mode) {
		return {
			id: "mode:" + mode.mode,
			kind: "mode",
			mode: mode.mode,
			name: mode.name,
			glyph: mode.glyph,
			keywords: mode.keywords || []
		};
	});
}

function groupEntries(groups) {
	return (groups || []).map(function (group) {
		return {
			id: "group:" + group.id,
			kind: "group",
			group: group.id,
			name: group.name,
			glyph: group.glyph,
			keywords: group.keywords || []
		};
	});
}

function collapsed(entries, aliases) {
	const skip = {};
	const names = {};

	Object.keys(aliases || {}).forEach(function (name) {
		const ids = aliases[name] || [];
		const present = ids.filter(function (id) { return entries[id] !== undefined; });
		const keep = present.length ? present[0] : undefined;

		if (keep === undefined)
			return;

		names[keep] = name;
		present.slice(1).forEach(function (id) { skip[id] = true; });
	});

	return { skip: skip, names: names };
}

function appEntries(entries, ignore, aliases) {
	const out = [];
	const skipIds = ignore || [];
	const folded = collapsed(entries || {}, aliases);

	Object.keys(entries || {}).forEach(function (id) {
		const entry = entries[id];

		if (!entry || !entry.name || !entry.exec || skipIds.indexOf(id) >= 0 || folded.skip[id])
			return;

		out.push({
			id: "app:" + id,
			kind: "app",
			appId: id,
			name: folded.names[id] || entry.name,
			keywords: [id].concat(entry.exec ? [entry.exec] : []),
			exec: entry.exec,
			execLine: entry.execLine,
			terminal: entry.terminal
		});
	});

	return out;
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

function customEntries(text) {
	return String(text === undefined || text === null ? "" : text).split("\n").map(function (line) {
		const parts = line.split("\t");
		const name = (parts[0] || "").trim();

		if (name === "")
			return null;

		return {
			id: "saved:" + name,
			kind: "saved",
			name: name,
			command: parts.length > 1 ? parts.slice(1).join("\t") : name,
			keywords: []
		};
	}).filter(function (entry) { return entry !== null; });
}

function formatCustom(list) {
	return (list || []).map(function (entry) { return entry.name + "\t" + entry.command; }).join("\n");
}

function toggleCustom(list, query) {
	const name = String(query === undefined || query === null ? "" : query).trim();
	const kept = (list || []).filter(function (entry) { return entry.name !== name; });

	if (name === "")
		return list || [];

	if (kept.length === (list || []).length) {
		kept.push({
			id: "saved:" + name,
			kind: "saved",
			name: name,
			command: name,
			keywords: []
		});
	}

	return kept;
}

function glyphOf(entry, config) {
	if (!entry)
		return "";
	if (entry.glyph)
		return entry.glyph;

	const kinds = {
		command: config.launcherIconCommand,
		saved: config.launcherIconCommand,
		window: config.launcherIconWindow,
		file: config.launcherIconFile,
		clip: config.launcherIconClipboard,
		calc: config.launcherIconCalc
	};

	return kinds[entry.kind] || "";
}

function rememberable(entry) {
	const kinds = ["app", "command", "action", "saved"];

	return Boolean(entry) && kinds.indexOf(entry.kind) >= 0;
}

function all(config, apps, saved) {
	return modeEntries(config.launcherModes)
		.concat(groupEntries(config.launcherGroups))
		.concat(saved || [])
		.concat(commandEntries(config.launcherCommands))
		.concat(actionEntries(config.launcherActions))
		.concat(apps || []);
}
