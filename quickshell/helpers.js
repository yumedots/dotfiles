.pragma library

function mixColor(c1, c2, t) {
	const parse = function (s) {
		const c = [];
		for (let i = 0; i < 3; i++)
			c.push(parseInt(s.substring(1 + 2 * i, 3 + 2 * i), 16));
		return c;
	};
	const a = parse(c1);
	const b = parse(c2);
	const clamped = Math.min(Math.max(t, 0), 1);
	let out = "#";
	for (let i = 0; i < 3; i++) {
		const v = Math.round(a[i] + (b[i] - a[i]) * clamped);
		out += v.toString(16).padStart(2, "0");
	}
	return out;
}

function orderedWindows(windows, workspaceId) {
	const field = function (win) {
		const here = win.workspace && win.workspace.id === workspaceId ? 0 : 1;
		const at = win.lastIpcObject && win.lastIpcObject.at ? win.lastIpcObject.at : [0, 0];

		return [here, win.workspace ? win.workspace.id : 0, at[0], at[1]];
	};

	return windows.slice().sort(function (a, b) {
		const fa = field(a);
		const fb = field(b);

		for (let i = 0; i < fa.length; i++) {
			if (fa[i] !== fb[i])
				return fa[i] - fb[i];
		}

		return 0;
	});
}

function nextIndex(list, value) {
	if (!list.length)
		return -1;

	return (list.indexOf(value) + 1) % list.length;
}

function filledCells(pct, cells) {
	return Math.min(Math.max(Math.round((pct / 100) * cells), 0), cells);
}

function daysInMonth(year, month) {
	return new Date(year, month + 1, 0).getDate();
}

function mondayIndex(date) {
	return (date.getDay() + 6) % 7;
}

function clampedDay(day, year, month) {
	return Math.min(Math.max(day, 1), daysInMonth(year, month));
}

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

function launchCommand(entry, appId) {
	const command = entry && entry.exec ? entry.exec : appId;

	if (entry && entry.terminal)
		return ["foot", "-e", command];

	return [command];
}

function parseDesktopEntries(text) {
	const entries = {};

	text.split("\n").forEach(function (line) {
		const path = line.substring(0, line.indexOf(":"));
		const equal = line.indexOf("=");

		if (!path || equal < 0)
			return;

		const key = line.substring(path.length + 1, equal);
		const value = line.substring(equal + 1);
		const id = path.substring(path.lastIndexOf("/") + 1).replace(/\.desktop$/, "");
		const entry = entries[id] || { id: id };

		entries[id] = entry;

		if (key === "NoDisplay" || key === "Hidden")
			entry.hidden = value === "true";
		else if (key === "Name" && !entry.name)
			entry.name = value;
		else if (key === "Icon" && !entry.icon)
			entry.icon = value;
		else if (key === "StartupWMClass" && !entry.wmclass)
			entry.wmclass = value;
		else if (key === "Terminal")
			entry.terminal = value === "true";
		else if (key === "Exec" && !entry.exec) {
			const command = value.split(/\s+/)[0];

			entry.exec = command.substring(command.lastIndexOf("/") + 1);
		}
	});

	return entries;
}

function lookupApp(entries, name) {
	if (!name)
		return null;

	const wanted = name.toLowerCase();
	const usable = function (entry) {
		return entry && !entry.hidden && entry.icon;
	};

	if (usable(entries[wanted]))
		return entries[wanted];

	const keys = Object.keys(entries);
	const fields = ["wmclass", "exec", "name"];

	for (let i = 0; i < fields.length; i++) {
		for (let j = 0; j < keys.length; j++) {
			const entry = entries[keys[j]];

			if (usable(entry) && entry[fields[i]] && entry[fields[i]].toLowerCase() === wanted)
				return entry;
		}
	}

	return null;
}
