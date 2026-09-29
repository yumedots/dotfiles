.pragma library

function trimNumber(value) {
	return numberText(value, 2);
}

function parseMode(mode) {
	const text = String(mode === undefined || mode === null ? "" : mode).replace(/Hz$/i, "").trim();
	const match = /^(\d+)x(\d+)(?:@([\d.]+))?/.exec(text);

	if (match === null)
		return null;

	return {
		width: parseInt(match[1], 10),
		height: parseInt(match[2], 10),
		refresh: match[3] === undefined ? 0 : Math.round(parseFloat(match[3]) * 100) / 100
	};
}

function modeText(mode) {
	if (mode === null || mode === undefined)
		return "";

	return mode.width + "x" + mode.height + (mode.refresh > 0 ? "@" + Math.round(mode.refresh) : "");
}

function sameMode(left, right) {
	if (left === null || left === undefined || right === null || right === undefined)
		return false;

	return left.width === right.width && left.height === right.height && Math.round(left.refresh) === Math.round(right.refresh);
}

function modeRank(mode) {
	return mode.width * mode.height * 1000 + mode.refresh;
}

function integral(value) {
	return Math.abs(value - Math.round(value)) < 0.000001;
}

const scaleGrid = 120;

function onScaleGrid(width, height, step) {
	return integral(width * scaleGrid / step) && integral(height * scaleGrid / step);
}

function scaleSteps(monitor, min, max) {
	const low = Number(min) > 0 ? Number(min) : 1;
	const high = Number(max) > low ? Number(max) : 2;

	if (monitor === null || monitor === undefined || !(monitor.width > 0) || !(monitor.height > 0))
		return [];

	const out = [];

	for (let step = Math.ceil(low * scaleGrid); step <= Math.floor(high * scaleGrid); step++) {
		if (onScaleGrid(monitor.width, monitor.height, step))
			out.push(step / scaleGrid);
	}

	return out;
}

function cleanScale(monitor, target) {
	const wanted = Number(target);
	const list = scaleSteps(monitor, 0.05, 4);

	if (!(wanted > 0) || list.length === 0)
		return wanted;

	let best = wanted;
	let bestGap = Infinity;

	list.forEach(function (value) {
		const gap = Math.abs(value - wanted);

		if (gap < bestGap - 1e-9) {
			bestGap = gap;
			best = value;
		}
	});

	return best;
}

function sameScale(left, right) {
	return Math.abs(Number(left) - Number(right)) < 0.005;
}

function modesOf(monitor) {
	const seen = {};
	const out = [];
	const listed = (Array.isArray(monitor.availableModes) ? monitor.availableModes : []).map(parseMode);

	listed.push({ width: monitor.width, height: monitor.height, refresh: Math.round((monitor.refreshRate || 0) * 100) / 100 });

	listed.forEach(function (mode) {
		if (mode === null || !(mode.width > 0))
			return;

		const key = modeText(mode);

		if (seen[key] === true)
			return;

		seen[key] = true;
		out.push(mode);
	});

	return out.sort(function (left, right) { return modeRank(right) - modeRank(left); });
}

function monitorsFromText(text) {
	let list = null;

	try {
		list = JSON.parse(String(text === undefined || text === null ? "" : text));
	} catch (error) {
		list = null;
	}

	if (!Array.isArray(list))
		return [];

	return list.map(function (monitor) {
		return {
			name: String(monitor.name === undefined || monitor.name === null ? "" : monitor.name),
			description: String(monitor.description || ""),
			width: monitor.width,
			height: monitor.height,
			refresh: Math.round((monitor.refreshRate || 0) * 100) / 100,
			scale: monitor.scale > 0 ? monitor.scale : 1,
			focused: monitor.focused === true,
			modes: modesOf(monitor)
		};
	});
}

function findMonitor(list, name) {
	if (!Array.isArray(list) || list.length === 0)
		return null;

	if (name !== undefined && name !== null && name !== "") {
		const named = list.filter(function (monitor) { return monitor.name === name; })[0];

		if (named !== undefined)
			return named;
	}

	const focused = list.filter(function (monitor) { return monitor.focused; })[0];

	return focused === undefined ? list[0] : focused;
}

function resolutionsOf(monitor) {
	if (monitor === null || monitor === undefined)
		return [];

	const seen = {};
	const out = [];

	(monitor.modes || []).forEach(function (mode) {
		const key = mode.width + "x" + mode.height;

		if (seen[key] === true)
			return;

		seen[key] = true;
		out.push({ width: mode.width, height: mode.height, label: key });
	});

	return out;
}

function refreshesFor(monitor, size) {
	if (monitor === null || monitor === undefined || size === null || size === undefined)
		return [];

	return (monitor.modes || []).filter(function (mode) {
		return mode.width === size.width && mode.height === size.height;
	});
}

function refreshLabel(monitor) {
	return monitor === null || monitor === undefined || !(monitor.refresh > 0) ? "" : Math.round(monitor.refresh) + " Hz";
}

function scaleLabel(scale) {
	return trimNumber(scale > 0 ? scale : 1) + "x";
}

function stateFromText(text) {
	const state = { fontSize: 0, iconSize: 0, fallback: null, outputs: {} };
	const lines = String(text === undefined || text === null ? "" : text).split("\n");

	lines.forEach(function (line) {
		let match = /^\s*fontSize\s*=\s*(\d+)/.exec(line);

		if (match !== null) {
			state.fontSize = parseInt(match[1], 10);
			return;
		}

		match = /^\s*iconSize\s*=\s*(\d+)/.exec(line);

		if (match !== null) {
			state.iconSize = parseInt(match[1], 10);
			return;
		}

		match = /^\s*fallback\s*=\s*{\s*mode\s*=\s*"([^"]*)",\s*scale\s*=\s*([\d.]+)/.exec(line);

		if (match !== null) {
			state.fallback = { mode: match[1], scale: parseFloat(match[2]) };
			return;
		}

		match = /^\s*\["([^"]+)"\]\s*=\s*{\s*mode\s*=\s*"([^"]*)",\s*scale\s*=\s*([\d.]+)/.exec(line);

		if (match !== null)
			state.outputs[match[1]] = { mode: match[2], scale: parseFloat(match[3]) };
	});

	return state;
}

function numberText(value, digits) {
	const number = Number(value);
	const unit = Math.pow(10, digits === undefined ? 6 : digits);

	if (!isFinite(number))
		return "1";

	return String(Math.round(number * unit) / unit);
}

function renderLua(state) {
	const fallback = state.fallback === null || state.fallback === undefined ? { mode: "", scale: 1 } : state.fallback;
	const names = Object.keys(state.outputs || {}).sort();
	const lines = [
		"return {",
		"\tfontSize = " + Math.round(state.fontSize || 0) + ",",
		"\ticonSize = " + Math.round(state.iconSize || 0) + ",",
		"\tfallback = { mode = \"" + fallback.mode + "\", scale = " + numberText(fallback.scale) + " },",
		"\toutputs = {"
	];

	names.forEach(function (name) {
		const entry = state.outputs[name];

		lines.push("\t\t[\"" + name + "\"] = { mode = \"" + entry.mode + "\", scale = " + numberText(entry.scale) + " },");
	});

	lines.push("\t},", "}");

	return lines.join("\n") + "\n";
}

function setOutput(state, name, patch) {
	const outputs = {};

	Object.keys(state.outputs || {}).forEach(function (key) {
		outputs[key] = { mode: state.outputs[key].mode, scale: state.outputs[key].scale };
	});

	const entry = outputs[name] === undefined ? { mode: "", scale: 1 } : outputs[name];

	if (patch.mode !== undefined)
		entry.mode = patch.mode;
	if (patch.scale !== undefined)
		entry.scale = patch.scale;

	outputs[name] = entry;

	return { fontSize: state.fontSize, iconSize: state.iconSize, fallback: state.fallback, outputs: outputs };
}

function setFontSize(state, size) {
	const ratio = state.fontSize > 0 && state.iconSize > 0 ? state.iconSize / state.fontSize : 10 / 12;

	return {
		fontSize: Math.round(size),
		iconSize: Math.max(1, Math.round(size * ratio)),
		fallback: state.fallback,
		outputs: state.outputs
	};
}

function rowNames() {
	return ["scale", "refresh", "font", "resolution"];
}

function moveCursor(rows, listCount, row, step, delta) {
	const bars = rows.length - 1;
	const total = bars + Math.max(0, listCount);

	if (bars < 0 || total <= 0)
		return { row: 0, step: -1 };

	const at = row < bars ? row : bars + Math.max(0, step);
	const next = ((at + delta) % total + total) % total;

	if (next < bars)
		return { row: next, step: -1 };

	return { row: bars, step: next - bars };
}

function displayDefaults(monitor) {
	if (monitor === null || monitor === undefined)
		return { mode: "", scale: 1 };

	const best = monitor.modes && monitor.modes.length > 0 ? monitor.modes[0] : { width: monitor.width, height: monitor.height, refresh: monitor.refresh };

	return { mode: modeText(best), scale: cleanScale(monitor, monitor.scale > 0 ? monitor.scale : 1) };
}

function detect(text, fontSize, iconSize) {
	const list = monitorsFromText(text);
	const outputs = {};

	list.forEach(function (monitor) {
		if (monitor.name === "")
			return;

		outputs[monitor.name] = displayDefaults(monitor);
	});

	return {
		fontSize: fontSize,
		iconSize: iconSize,
		fallback: displayDefaults(list.length > 0 ? list[0] : null),
		outputs: outputs
	};
}
