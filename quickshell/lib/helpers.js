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

function filledCells(pct, cells) {
	return Math.min(Math.max(Math.round((pct / 100) * cells), 0), cells);
}

function parseGradient(text) {
	const parts = String(text || "").trim().split(/\s+/);
	const colors = [];
	let angle = 0;

	parts.forEach(function (part) {
		const degrees = /^(-?[0-9.]+)deg$/i.exec(part);

		if (degrees) {
			angle = parseFloat(degrees[1]);
			return;
		}

		if (/^[0-9a-f]{6}([0-9a-f]{2})?$/i.test(part))
			colors.push("#" + part.toLowerCase());
	});

	return { colors: colors.length ? colors : null, angle: angle };
}

function colorChannels(text) {
	const value = String(text === undefined || text === null ? "" : text).replace("#", "").trim().toLowerCase();

	if (!/^[0-9a-f]+$/.test(value) || (value.length !== 6 && value.length !== 8))
		return null;

	const hex = value.length === 6 ? "ff" + value : value;

	return [0, 2, 4, 6].map(function (at) { return parseInt(hex.substring(at, at + 2), 16); });
}

function pick(mono, color, monoColor) {
	return mono ? monoColor : color;
}

function mixColors(c1, c2, t) {
	const a = colorChannels(c1);
	const b = colorChannels(c2);

	if (!a || !b)
		return c1;

	const clamped = Math.min(Math.max(t, 0), 1);

	return "#" + a.map(function (channel, i) {
		return Math.round(channel + (b[i] - channel) * clamped).toString(16).padStart(2, "0");
	}).join("");
}

function gradientSample(colors, t) {
	if (!colors || !colors.length)
		return null;
	if (colors.length < 2)
		return colors[0];

	return mixColors(colors[0], colors[colors.length - 1], t);
}

function gradientEdgeColors(colors, angle, width, height, edge) {
	const span = Math.max(width, height) * 1.5;
	const radians = (angle === undefined || angle === null ? 0 : angle) * Math.PI / 180;
	const cos = Math.cos(radians);
	const sin = Math.sin(radians);
	const at = function (x, y) {
		return ((x - width / 2) * cos + (y - height / 2) * sin + span / 2) / span;
	};
	const ends = edge === "bottom" ? [[0, height], [width, height]]
		: edge === "left" ? [[0, 0], [0, height]]
			: edge === "right" ? [[width, 0], [width, height]]
				: [[0, 0], [width, 0]];

	return {
		horizontal: edge === "top" || edge === "bottom",
		start: gradientSample(colors, at(ends[0][0], ends[0][1])),
		end: gradientSample(colors, at(ends[1][0], ends[1][1]))
	};
}

function gradientEdges(colors, angle, width, height, thickness) {
	const sides = ["top", "bottom", "left", "right"];

	return sides.map(function (edge) {
		const sample = gradientEdgeColors(colors, angle, width, height, edge);
		const long = edge === "top" || edge === "bottom";

		return {
			edge: edge,
			x: edge === "right" ? width - thickness : 0,
			y: edge === "bottom" ? height - thickness : (long ? 0 : thickness),
			width: long ? width : thickness,
			height: long ? thickness : Math.max(0, height - thickness * 2),
			horizontal: sample.horizontal,
			start: sample.start,
			end: sample.end
		};
	});
}

function parseHyprBorder(text) {
	const border = { colors: null, angle: 0, width: null };

	String(text || "").split("\n").forEach(function (line) {
		if (!line.trim())
			return;

		let option;

		try {
			option = JSON.parse(line);
		} catch (error) {
			return;
		}

		if (option.gradient) {
			const gradient = parseGradient(option.gradient);

			border.colors = gradient.colors || border.colors;
			border.angle = gradient.angle;
		} else if (typeof option.int === "number" && String(option.option).indexOf("border_size") >= 0)
			border.width = option.int;
	});

	return border;
}

function parseHyprGaps(text) {
	const gaps = { inner: null, outer: null };

	String(text || "").split("\n").forEach(function (line) {
		if (!line.trim())
			return;

		let option;

		try {
			option = JSON.parse(line);
		} catch (error) {
			return;
		}

		const raw = option.css !== undefined ? option.css : option.int;

		if (raw === undefined)
			return;

		const value = parseFloat(String(raw).trim().split(/\s+/)[0]);

		if (isNaN(value))
			return;

		if (String(option.option).indexOf("gaps_out") >= 0)
			gaps.outer = value;
		else if (String(option.option).indexOf("gaps_in") >= 0)
			gaps.inner = value;
	});

	return gaps;
}

function isOutputStream(isStream, mediaClass) {
	if (!isStream)
		return false;

	return String(mediaClass === undefined || mediaClass === null ? "" : mediaClass).indexOf("Input") < 0;
}

function isInputStream(isStream, mediaClass) {
	if (!isStream)
		return false;

	return String(mediaClass === undefined || mediaClass === null ? "" : mediaClass).indexOf("Input") >= 0;
}

function streamApp(props) {
	const values = props || {};
	const binary = String(values["application.process.binary"] || "");
	const icons = [];

	if (values["application.icon-name"])
		icons.push(String(values["application.icon-name"]));
	if (values["application.name"])
		icons.push(String(values["application.name"]).toLowerCase());
	if (binary)
		icons.push(binary.substring(binary.lastIndexOf("/") + 1));

	return {
		name: values["application.name"] || values["node.description"] || values["node.name"] || "",
		icons: icons
	};
}

function parseRunningStreams(text, direction) {
	let dump;

	try {
		dump = JSON.parse(text);
	} catch (error) {
		return [];
	}

	const wanted = direction === "input" ? "Stream/Input" : "Stream/Output";
	const ids = [];

	(dump || []).forEach(function (object) {
		if (!object || object.type !== "PipeWire:Interface:Node")
			return;

		const info = object.info || {};
		const props = info.props || {};

		if (String(props["media.class"] || "").indexOf(wanted) < 0)
			return;
		if (info.state !== "running")
			return;

		ids.push(object.id);
	});

	return ids;
}

function pageCount(contentWidth, viewWidth, step) {
	if (viewWidth <= 0 || step <= 0 || contentWidth <= viewWidth)
		return 1;

	return Math.ceil((contentWidth - viewWidth) / step) + 1;
}

function pageOffset(page, contentWidth, viewWidth, step) {
	const last = Math.max(0, contentWidth - viewWidth);
	const wanted = Math.max(0, Math.floor(page)) * step;

	return Math.max(0, Math.min(wanted, last));
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

function shiftYears(date, years) {
	const next = new Date(date.getTime());
	const day = next.getDate();

	next.setDate(1);
	next.setFullYear(next.getFullYear() + years);
	next.setDate(Math.min(day, daysInMonth(next.getFullYear(), next.getMonth())));

	return next;
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

function shellQuote(arg) {
	return "'" + arg.replace(/'/g, "'\\''") + "'";
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
			const command = value.split(/\s+/)[0].replace(/["']/g, "");

			entry.exec = command.substring(command.lastIndexOf("/") + 1);
			entry.execLine = cleanExec(value);
		}
	});

	return entries;
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

		if (!entry || entry.hidden || !entry.name || !entry.exec || skip.indexOf(id) >= 0)
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

function calculate(expression) {
	const text = String(expression === undefined || expression === null ? "" : expression).replace(/\s+/g, "");

	if (!text)
		return null;

	const constants = { pi: Math.PI, e: Math.E };
	const functions = { sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil };
	let at = 0;

	function eat(character) {
		if (text[at] === character) {
			at += 1;
			return true;
		}

		return false;
	}

	function parseExpression() {
		let value = parseTerm();

		if (value === null)
			return null;

		for (;;) {
			if (eat("+")) {
				const right = parseTerm();

				if (right === null)
					return null;
				value += right;
			} else if (eat("-")) {
				const right = parseTerm();

				if (right === null)
					return null;
				value -= right;
			} else
				return value;
		}
	}

	function parseTerm() {
		let value = parsePower();

		if (value === null)
			return null;

		for (;;) {
			if (eat("*")) {
				const right = parsePower();

				if (right === null)
					return null;
				value *= right;
			} else if (eat("/")) {
				const right = parsePower();

				if (right === null || right === 0)
					return null;
				value /= right;
			} else if (eat("%")) {
				const right = parsePower();

				if (right === null || right === 0)
					return null;
				value %= right;
			} else
				return value;
		}
	}

	function parsePower() {
		const base = parseUnary();

		if (base === null)
			return null;
		if (!eat("^"))
			return base;

		const exponent = parsePower();

		return exponent === null ? null : Math.pow(base, exponent);
	}

	function parseUnary() {
		if (eat("-")) {
			const value = parseUnary();

			return value === null ? null : -value;
		}
		if (eat("+"))
			return parseUnary();

		return parseAtom();
	}

	function parseAtom() {
		if (eat("(")) {
			const value = parseExpression();

			return value === null || !eat(")") ? null : value;
		}

		const word = /^[a-zA-Z]+/.exec(text.substring(at));

		if (word) {
			at += word[0].length;

			if (eat("(")) {
				const argument = parseExpression();

				if (argument === null || !eat(")") || !functions[word[0]])
					return null;

				return functions[word[0]](argument);
			}

			return constants[word[0]] === undefined ? null : constants[word[0]];
		}

		const number = /^[0-9]*\.?[0-9]+/.exec(text.substring(at));

		if (!number)
			return null;

		at += number[0].length;

		return parseFloat(number[0]);
	}

	const result = parseExpression();

	if (result === null || at !== text.length || !isFinite(result))
		return null;

	return result;
}

function formatNumber(value) {
	if (value === null || value === undefined || !isFinite(value))
		return "";

	return String(Math.round(value * 1000000) / 1000000);
}

function fileSearchCommand(home, query, depth, max, skip) {
	const skipNames = skip || [];
	const prune = skipNames.map(function (name) { return "-name " + shellQuote(name); }).join(" -o ");
	const inside = (prune ? "\\( " + prune + " \\) -prune -o " : "") + "-iname " + shellQuote("*" + query + "*") + " -print";

	return ["sh", "-c", "find " + shellQuote(home) + " -maxdepth " + Math.max(1, Math.floor(depth)) + " "
		+ inside + " 2>/dev/null | head -n " + Math.max(1, Math.floor(max))];
}

function parseClipboardList(text) {
	const entries = [];

	String(text || "").split("\n").forEach(function (line) {
		const tab = line.indexOf("\t");

		if (tab <= 0)
			return;

		const id = line.substring(0, tab).trim();
		const preview = line.substring(tab + 1).trim();

		if (id !== "" && preview !== "")
			entries.push({ id: id, text: preview });
	});

	return entries;
}

function calcEntry(query) {
	const text = String(query === undefined || query === null ? "" : query).trim();

	if (!/[0-9]/.test(text))
		return null;

	const value = calculate(text);

	if (value === null)
		return null;

	const out = formatNumber(value);

	if (out === text)
		return null;

	return { id: "calc", kind: "calc", name: text + " = " + out, keywords: [], value: out };
}

function pathLines(text) {
	return String(text || "").split("\n").map(function (line) { return line.trim(); }).filter(function (line) { return line !== ""; });
}

function cpuSample(fields) {
	let total = 0;
	let idle = 0;

	for (let i = 1; i < fields.length; i++) {
		const n = parseFloat(fields[i]);

		if (isNaN(n))
			continue;

		total += n;
		if (i === 4 || i === 5)
			idle += n;
	}

	return { total: total, idle: idle };
}

function parseCpuStat(text) {
	const out = { total: { total: 0, idle: 0 }, cores: [] };

	String(text || "").split("\n").forEach(function (line) {
		const fields = line.trim().split(/\s+/);

		if (fields[0] !== "cpu" && !/^cpu[0-9]+$/.test(fields[0]))
			return;

		if (fields[0] === "cpu")
			out.total = cpuSample(fields);
		else
			out.cores.push(cpuSample(fields));
	});

	return out;
}

function cpuLoad(now, before) {
	if (!now || !before)
		return 0;

	const dt = now.total - before.total;

	if (dt <= 0)
		return 0;

	return Math.min(Math.max(100 * (1 - (now.idle - before.idle) / dt), 0), 100);
}

function cpuPercents(prev, now) {
	const out = { all: 0, cores: [] };

	if (!now || !now.cores)
		return out;

	out.all = cpuLoad(now.total, prev ? prev.total : null);
	out.cores = now.cores.map(function (core, i) {
		return cpuLoad(core, prev && prev.cores && prev.cores[i] ? prev.cores[i] : null);
	});

	return out;
}

function parseCpuInfo(text) {
	const info = { model: "", cores: 0, threads: 0, mhz: 0, cache: 0 };

	String(text || "").split("\n").forEach(function (line) {
		const at = line.indexOf(":");

		if (at < 0)
			return;

		const key = line.substring(0, at).trim();
		const value = line.substring(at + 1).trim();

		if (key === "processor")
			info.threads += 1;
		else if (key === "model name" && !info.model)
			info.model = value;
		else if (key === "cpu cores" && !info.cores)
			info.cores = parseInt(value, 10) || 0;
		else if (key === "cpu MHz")
			info.mhz = Math.max(info.mhz, parseFloat(value) || 0);
		else if (key === "cache size" && !info.cache)
			info.cache = parseFloat(value) || 0;
	});

	if (!info.cores)
		info.cores = info.threads;

	return info;
}

function cpuSpecLine(info) {
	const parts = [];
	const i = info || {};

	if (i.threads)
		parts.push(i.threads + " threads");
	if (i.cores && i.cores !== i.threads)
		parts.push(i.cores + " cores");
	if (i.mhz)
		parts.push((i.mhz / 1000).toFixed(1) + " GHz");
	if (i.cache)
		parts.push(i.cache >= 1024 ? Math.round(i.cache / 1024) + " MB" : i.cache + " KB");

	return parts.join(" · ");
}

function parseTopProcesses(text) {
	const psCommWidth = 16;
	const out = [];

	String(text || "").split("\n").forEach(function (line) {
		const match = /^\s*([0-9]+(?:\.[0-9]+)?)\s+([0-9]+)\s+(.+?)\s*$/.exec(line);

		if (!match)
			return;

		const rest = match[3];
		const name = rest.slice(0, psCommWidth).trim();

		if (name === "")
			return;

		out.push({ name: name, pid: parseInt(match[2], 10), value: parseFloat(match[1]), cmd: rest.slice(psCommWidth).trim() });
	});

	return out;
}

function filterProcesses(procs, ignore, query, max) {
	const skip = ignore || [];
	const wanted = String(query === undefined || query === null ? "" : query).toLowerCase();
	const kept = (procs || []).filter(function (proc) {
		return skip.indexOf(proc.name) < 0
			&& (proc.name.toLowerCase().indexOf(wanted) >= 0 || String(proc.cmd || "").toLowerCase().indexOf(wanted) >= 0);
	});

	return max > 0 ? kept.slice(0, max) : kept;
}

function killCommand(pid, signal) {
	if (!pid)
		return [];

	return ["kill", signal || "-9", String(pid)];
}

function parseMeminfo(text) {
	const vals = {};

	String(text || "").split("\n").forEach(function (line) {
		const at = line.indexOf(":");

		if (at < 0)
			return;

		vals[line.substring(0, at).trim()] = parseFloat(line.substring(at + 1)) || 0;
	});

	const total = vals["MemTotal"] || 0;
	const available = vals["MemAvailable"] || (vals["MemFree"] || 0) + (vals["Buffers"] || 0) + (vals["Cached"] || 0);
	const used = Math.max(0, total - available);
	const cached = vals["Cached"] || 0;
	const buffers = vals["Buffers"] || 0;
	const swapTotal = vals["SwapTotal"] || 0;
	const swapUsed = Math.max(0, swapTotal - (vals["SwapFree"] || 0));
	const pool = total + swapTotal;
	const committed = used + swapUsed;

	return {
		total: total,
		used: used,
		available: available,
		cached: cached,
		buffers: buffers,
		swapTotal: swapTotal,
		swapUsed: swapUsed,
		pool: pool,
		committed: committed,
		ramFree: Math.max(0, total - used - cached - buffers),
		swapFree: Math.max(0, swapTotal - swapUsed),
		free: Math.max(0, pool - committed - cached - buffers),
		pct: pool > 0 ? 100 * committed / pool : 0
	};
}

function dangerColor(base, warn, danger, warnAt, dangerAt, pct) {
	if (pct <= warnAt)
		return mixColors(base, warn, warnAt > 0 ? pct / warnAt : 1);

	if (pct >= dangerAt)
		return mixColors(danger, danger, 1);

	return mixColors(warn, danger, dangerAt > warnAt ? (pct - warnAt) / (dangerAt - warnAt) : 1);
}


function gbText(kb) {
	return (kb / 1024 / 1024).toFixed(1) + " GB";
}

function sizeText(kb) {
	if (kb >= 1024 * 1024)
		return (kb / 1024 / 1024).toFixed(1) + " GB";

	if (kb >= 1024)
		return (kb / 1024).toFixed(1) + " MB";

	return Math.round(kb) + " KB";
}

function topProcesses(procs, ignore, max) {
	const skip = ignore || [];
	const kept = (procs || []).filter(function (proc) {
		return skip.indexOf(proc.name) < 0;
	});

	return max > 0 ? kept.slice(0, max) : kept;
}

function holdProcessOrder(previous, incoming) {
	const rows = incoming || [];
	const held = previous || [];

	if (held.length === 0)
		return rows;

	const alive = {};
	const out = [];
	const stale = [];

	rows.forEach(function (row) {
		alive[row.pid] = row;
	});

	held.forEach(function (row) {
		const fresh = alive[row.pid];

		if (fresh === undefined) {
			out.push(row);
			stale.push(out.length - 1);
			return;
		}

		out.push(fresh);
		delete alive[row.pid];
	});

	const spare = [];

	rows.forEach(function (row) {
		if (alive[row.pid] !== undefined) {
			spare.push(row);
			delete alive[row.pid];
		}
	});

	let used = 0;

	stale.forEach(function (slot) {
		if (used < spare.length)
			out[slot] = spare[used++];
	});

	return out.concat(spare.slice(used));
}

function barLayoutDefault() {
	return {
		position: "top",
		transparent: false,
		centerAnchor: "clock",
		left: [{ id: "workspaces" }],
		center: [{ id: "clock" }],
		right: [{ id: "tray" }, { id: "notify" }, { id: "cpu" }, { id: "memory" }, { id: "volume" }, { id: "github" }]
	};
}

function parseBarLayout(text) {
	const fallback = barLayoutDefault();
	let data;

	try {
		data = JSON.parse(String(text === undefined || text === null ? "" : text));
	} catch (error) {
		return fallback;
	}

	const bar = data && data.bar ? data.bar : {};
	const layout = bar.layout ? bar.layout : {};
	const slot = function (name) {
		const list = layout[name];

		if (!Array.isArray(list))
			return fallback[name];

		return list.filter(function (entry) { return entry && typeof entry.id === "string" && entry.id !== ""; });
	};

	return {
		position: bar.position === "bottom" ? "bottom" : "top",
		transparent: bar.transparent === true,
		centerAnchor: typeof bar.centerAnchor === "string" ? bar.centerAnchor : fallback.centerAnchor,
		left: slot("left"),
		center: slot("center"),
		right: slot("right")
	};
}

function plainText(html) {
	return String(html || "")
		.replace(/<br\s*\/?>/gi, " ")
		.replace(/<[^>]*>/g, "")
		.replace(/&lt;/g, "<")
		.replace(/&gt;/g, ">")
		.replace(/&quot;/g, "\"")
		.replace(/&#39;/g, "'")
		.replace(/&nbsp;/g, " ")
		.replace(/&amp;/g, "&")
		.replace(/\s+/g, " ")
		.trim();
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

function weatherGeoUrl(place) {
	const city = String(place || "").split(",")[0].trim();

	return "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(city) + "&count=8&language=en&format=json";
}

function weatherRegion(place) {
	const parts = String(place || "").split(",");

	return parts.length > 1 ? parts.slice(1).join(",").trim() : "";
}

function parseWeatherGeo(text, region) {
	let data = null;

	try {
		data = JSON.parse(text);
	} catch (error) {
		data = null;
	}

	const list = (data && data.results) || [];

	if (list.length === 0)
		return null;

	const want = String(region || "").toLowerCase();
	let hit = list[0];

	if (want !== "") {
		for (let i = 0; i < list.length; i++) {
			const row = list[i];
			const area = String(row.admin1 || "").toLowerCase();
			const country = String(row.country || "").toLowerCase();
			const code = String(row.country_code || "").toLowerCase();

			if (area.indexOf(want) === 0 || area === want || country.indexOf(want) === 0 || code === want) {
				hit = row;
				break;
			}
		}
	}

	return {
		lat: hit.latitude,
		lon: hit.longitude,
		place: [hit.name, hit.admin1].filter(function (part) { return part; }).join(", ")
	};
}

function parseCoords(text) {
	const match = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/.exec(String(text || ""));

	return match ? { lat: parseFloat(match[1]), lon: parseFloat(match[2]) } : null;
}

function weatherForecastUrl(lat, lon) {
	return "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
		+ "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,precipitation"
		+ "&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto";
}

function parseWeatherCurrent(text) {
	let data = null;

	try {
		data = JSON.parse(text);
	} catch (error) {
		data = null;
	}

	const current = data && data.current;

	if (!current || typeof current.weather_code !== "number")
		return null;

	const unit = String((data.current_units || {}).temperature_2m || "°F").replace(/\s/g, "");

	return {
		code: Math.round(current.weather_code),
		precip: Number(current.precipitation) || 0,
		temp: Math.round(current.temperature_2m) + unit,
		feels: Math.round(current.apparent_temperature) + unit,
		wind: Math.round(current.wind_speed_10m) + "mph",
		humidity: Math.round(current.relative_humidity_2m) + "%"
	};
}

function splitTemp(temp) {
	const match = /^([+-]?\d+(?:\.\d+)?)\s*(.*)$/.exec(String(temp || "").trim());

	if (!match)
		return { value: String(temp || "").trim(), unit: "" };

	return { value: match[1], unit: match[2] };
}

function weatherPointsUrl(lat, lon) {
	return "https://api.weather.gov/points/" + lat + "," + lon;
}

function weatherObservationUrl(id) {
	return "https://api.weather.gov/stations/" + id + "/observations/latest";
}

function weatherRequest(urls) {
	return "curl -sL -m 15 -H " + shellQuote("User-Agent: quickshell-weather (weather@example.com) ") + " -w '\n@@QS@@\n' " + urls;
}

function weatherBody(text) {
	return String(text || "").split("@@QS@@")[0];
}

function parseWeatherPoints(text) {
	let data = null;

	try {
		data = JSON.parse(weatherBody(text));
	} catch (error) {
		data = null;
	}

	const props = data && data.properties;

	if (!props || !props.observationStations)
		return null;

	return props.observationStations;
}

function stationDistance(lat, lon, stationLat, stationLon) {
	const dx = (stationLon - lon) * 0.9;
	const dy = stationLat - lat;

	return dx * dx + dy * dy;
}

function parseWeatherStationIds(text, lat, lon, count) {
	let data = null;

	try {
		data = JSON.parse(weatherBody(text));
	} catch (error) {
		data = null;
	}

	const rows = [];
	const feats = (data && data.features) || [];

	for (let i = 0; i < feats.length; i++) {
		const props = feats[i].properties || {};
		const coords = (feats[i].geometry || {}).coordinates || [];

		if (!props.stationIdentifier || coords.length < 2)
			continue;

		rows.push({ id: props.stationIdentifier, d: stationDistance(lat, lon, coords[1], coords[0]) });
	}

	rows.sort(function (a, b) { return a.d - b.d; });

	return rows.slice(0, count).map(function (row) { return row.id; });
}

function weatherCodeFromText(text) {
	const line = String(text || "").toLowerCase();

	if (line === "")
		return -1;

	if (line.indexOf("thunder") >= 0)
		return 95;

	if (line.indexOf("hail") >= 0)
		return 96;

	if (line.indexOf("freezing") >= 0 || line.indexOf("sleet") >= 0)
		return 66;

	if (line.indexOf("heavy rain") >= 0 || line.indexOf("heavy shower") >= 0)
		return 65;

	if (line.indexOf("rain") >= 0 || line.indexOf("drizzle") >= 0 || line.indexOf("shower") >= 0)
		return 61;

	if (line.indexOf("heavy snow") >= 0 || line.indexOf("blizzard") >= 0)
		return 75;

	if (line.indexOf("snow") >= 0)
		return 71;

	if (line.indexOf("fog") >= 0 || line.indexOf("mist") >= 0 || line.indexOf("haze") >= 0)
		return 45;

	if (line.indexOf("partly") >= 0 || line.indexOf("mostly sunny") >= 0 || line.indexOf("mostly clear") >= 0)
		return 2;

	if (line.indexOf("overcast") >= 0 || line.indexOf("cloudy") >= 0)
		return 3;

	if (line.indexOf("clear") >= 0 || line.indexOf("sunny") >= 0)
		return 0;

	return -1;
}

function parseWeatherObservations(text) {
	const chunks = String(text || "").split("@@QS@@");
	const rows = [];

	for (let i = 0; i < chunks.length; i++) {
		let data = null;

		try {
			data = JSON.parse(chunks[i]);
		} catch (error) {
			data = null;
		}

		const props = data && data.properties;

		if (!props || !props.textDescription)
			continue;

		rows.push({
			text: props.textDescription,
			code: weatherCodeFromText(props.textDescription),
			precip: ((props.precipitationLastHour || {}).value) || 0
		});
	}

	return rows;
}

function weatherObservationCode(rows) {
	let first = -1;

	for (let i = 0; i < rows.length; i++) {
		const row = rows[i];

		if (row.code >= 51)
			return row.code;

		if (row.precip > 0)
			return 61;

		if (first < 0)
			first = row.code;
	}

	return first;
}

function weatherCodeFor(code, precip) {
	if (precip > 0 && code <= 48)
		return 61;

	return code;
}

function weatherCodeInfo(code, table, fallback) {
	const row = (table || {})[code];

	if (row)
		return row;

	return { name: "", glyph: fallback || "" };
}
