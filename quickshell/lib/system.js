.pragma library

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

function streamId(props) {
	const values = props || {};
	const binary = String(values["application.process.binary"] || "");

	return String(values["node.name"] || values["application.name"] || binary.substring(binary.lastIndexOf("/") + 1));
}

function streamIds(props) {
	const values = props || {};
	const binary = String(values["application.process.binary"] || "");
	const game = (String(values["node.name"] || values["application.name"] || "").match(/(\d{3,})\b/) || [])[1];
	const ids = [values["node.name"], values["application.name"], game ? "steam_app_" + game : "", binary.substring(binary.lastIndexOf("/") + 1)];

	return ids.filter(function (id) { return id; }).map(String);
}

function inputStream(node) {
	return !!node && String(node.class || "").indexOf("Input") >= 0;
}

function shownStream(node) {
	return !!node && node.ready === true && node.isStream === true && !inputStream(node);
}

function streamPlaying(node) {
	return !!node && node.running === true;
}

function streamNodes(nodes, onlyPlaying) {
	const list = [];

	(nodes || []).forEach(function (node) {
		if (shownStream(node) && (!onlyPlaying || streamPlaying(node)))
			list.push(node);
	});

	return list;
}

function streamHeld(node, held) {
	return !!node && !!held && held[node.id] !== undefined;
}

function streamVisible(node, onlyPlaying, held) {
	return shownStream(node) && (streamHeld(node, held) || !onlyPlaying || streamPlaying(node));
}

function anyStreamVisible(nodes, onlyPlaying, held) {
	return (nodes || []).some(function (node) {
		return streamVisible(node, onlyPlaying, held);
	});
}

function recordingStream(nodes) {
	return (nodes || []).some(function (node) {
		return !!node && node.isStream === true && node.running === true && inputStream(node);
	});
}

function audioDevices(nodes, input) {
	const found = [];

	(nodes || []).forEach(function (node) {
		if (!node || node.isStream || node.isSink === !!input)
			return;

		found.push(node);
	});

	return found;
}

function firstDevice(nodes, input) {
	const found = audioDevices(nodes, input);

	return found.length > 0 ? found[0] : null;
}

function holdStream(held, id, until) {
	const next = Object.assign({}, held || {});

	next[id] = until;

	return next;
}

function pruneHolds(held, now) {
	const next = {};

	Object.keys(held || {}).forEach(function (id) {
		if (held[id] > now)
			next[id] = held[id];
	});

	return next;
}

function sameNode(a, b) {
	return !!a && !!b && a.id === b.id;
}

function sortedDevices(nodes, input, active) {
	const found = audioDevices(nodes, input);
	let at = -1;

	for (let i = 0; i < found.length; i++) {
		if (sameNode(found[i], active))
			at = i;
	}

	if (at > 0) {
		found.splice(at, 1);
		found.unshift(active);
	}

	return found;
}

function nodeMuted(node) {
	return !!(node && node.mute);
}

function nodeVolume(node) {
	return node && node.volume !== undefined ? node.volume : 0;
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

function parseBattery(text) {
	const vals = {};

	String(text || "").split("\n").forEach(function (line) {
		const at = line.indexOf("=");

		if (at < 0)
			return;

		vals[line.substring(0, at).trim()] = line.substring(at + 1).trim();
	});

	if (vals["POWER_SUPPLY_PRESENT"] === "0" || vals["POWER_SUPPLY_CAPACITY"] === undefined)
		return null;

	const state = vals["POWER_SUPPLY_STATUS"] || "Unknown";

	return {
		pct: parseFloat(vals["POWER_SUPPLY_CAPACITY"]) || 0,
		charging: state === "Charging" || state === "Full",
		full: state === "Full"
	};
}

function batteryIcon(battery, icons) {
	if (!battery)
		return icons.plug;

	if (battery.charging)
		return icons.charge;

	const p = battery.pct;

	return p >= 90 ? icons.full
		: p >= 60 ? icons.high
		: p >= 30 ? icons.mid
		: p >= 10 ? icons.low
		: icons.alert;
}

function cpuGovernors(text) {
	const line = String(text || "").split("\n").filter(function (row) { return /\w/.test(row); }).pop();

	if (line === undefined || line.indexOf(":") >= 0)
		return [];

	return line.replace(/\[|\]/g, "").split(/\s+/).filter(function (word) { return /\w/.test(word); });
}

function currentGovernor(text) {
	const hit = String(text || "").split("\n").find(function (row) { return row.indexOf("[") >= 0; });

	return hit ? /\[([a-z_-]+)\]/.exec(hit)[1] : "";
}

function governorCommand(governor) {
	return ["sh", "-c", "echo '" + governor + "' | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"];
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
