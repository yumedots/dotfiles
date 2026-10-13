.pragma library

function splitTerse(line) {
	const out = [];
	let current = "";

	for (let i = 0; i < line.length; i++) {
		const ch = line[i];

		if (ch === "\\" && i + 1 < line.length) {
			current += line[i + 1];
			i++;
		} else if (ch === ":") {
			out.push(current);
			current = "";
		} else {
			current += ch;
		}
	}

	out.push(current);
	return out;
}

function rows(text) {
	return String(text === undefined || text === null ? "" : text).split("\n").filter(function (line) {
		return line.trim() !== "";
	});
}

function parseDevs(text) {
	return rows(text).map(function (line) {
		const field = splitTerse(line);

		if (field.length < 4)
			return null;

		return { device: field[0], type: field[1], state: field[2], connection: field[3] };
	}).filter(function (dev) {
		return dev !== null;
	});
}

function pickDev(devs) {
	const list = devs || [];

	return list.filter(function (dev) {
		return dev.type === "ethernet" || dev.type === "wifi";
	})[0] || null;
}

function parseRates(text) {
	const out = {};

	rows(text).forEach(function (line) {
		const part = line.trim().split(/\s+/);
		const name = part[0] ? part[0].replace(/:$/, "") : "";

		if (name === "" || name === "face" || part.length < 10)
			return;

		out[name] = { rx: Number(part[1]), tx: Number(part[9]) };
	});

	return out;
}

function parseShow(text) {
	const out = {};

	rows(text).forEach(function (line) {
		const at = line.indexOf(":");

		if (at > 0)
			out[line.slice(0, at)] = line.slice(at + 1);
	});

	return out;
}

function deviceInfo(text) {
	const show = parseShow(text);
	const dns = Object.keys(show).filter(function (key) {
		return key.indexOf("IP4.DNS[") === 0;
	}).map(function (key) {
		return show[key];
	});

	return {
		ip: show["IP4.ADDRESS[1]"] || "",
		gateway: show["IP4.GATEWAY"] || "",
		dns: dns[0] || ""
	};
}

function rateBetween(prev, now, iface, seconds) {
	const before = prev && prev[iface];
	const after = now && now[iface];

	if (!before || !after || !(seconds > 0))
		return { down: 0, up: 0 };

	return {
		down: Math.max(0, (after.rx - before.rx) / seconds),
		up: Math.max(0, (after.tx - before.tx) / seconds)
	};
}

function rateText(bytesPerSecond) {
	const value = Math.max(0, Number(bytesPerSecond) || 0);

	if (value >= 1024 * 1024)
		return (value / 1024 / 1024).toFixed(1) + " MB/s";

	if (value >= 1024)
		return (value / 1024).toFixed(0) + " KB/s";

	return Math.round(value) + " B/s";
}

function brailleMasks(values, peak, cells, dir) {
	const cols = cells * 2;
	const top = peak > 0 ? peak : 1;
	const count = values.length;
	const masks = [];

	for (let c = 0; c < cells; c++) {
		let mask = 0;

		for (let k = 0; k < 2; k++) {
			const at = Math.max(0, count - cols) + c * 2 + k;
			const sample = at < count ? values[at] : 0;
			const value = Math.max(0, Number(sample) || 0);
			let lit = Math.min(4, Math.ceil(value / top * 4));

			if (value > 0 && lit < 1)
				lit = 1;

			if (lit > 0) {
				const dots = (1 << lit) - 1;
				mask |= dir === "up" ? dots << (k * 4) : dots << (4 - lit) << (k * 4);
			}
		}

		masks.push(mask);
	}

	return masks;
}

function brailleGraph(values, peak, cells, dir) {
	return brailleMasks(values, peak, cells, dir).map(function (mask) {
		return String.fromCodePoint(0x2800 + mask);
	}).join("");
}

function megaText(bytesPerSecond) {
	return (Math.max(0, Number(bytesPerSecond) || 0) / 1024 / 1024).toFixed(1);
}

function signalBars(pct) {
	const value = Math.max(0, Math.min(100, Number(pct) || 0));

	if (value > 80)
		return 4;

	if (value > 55)
		return 3;

	if (value > 30)
		return 2;

	return value > 5 ? 1 : 0;
}

function parseWifiList(text) {
	return rows(text).map(function (line) {
		const field = splitTerse(line);

		if (field.length < 7)
			return null;

		return {
			active: field[0] === "*",
			ssid: field[1],
			signal: Number(field[2]) || 0,
			chan: field[3],
			freq: field[4],
			security: field[5],
			bssid: field[6]
		};
	}).filter(function (net) {
		return net !== null;
	});
}

function knownNetworks(text) {
	return rows(text).map(function (line) {
		const field = splitTerse(line);

		return field.length >= 2 ? { name: field[0], uuid: field[1] } : null;
	}).filter(function (net) {
		return net !== null && net.name !== "";
	});
}

function currentSignal(text) {
	const active = parseWifiList(text).filter(function (net) {
		return net.active;
	});

	return active.length > 0 ? active[0].signal : -1;
}

function connectCommand(ssid, password, hidden) {
	if (password && password !== "")
		return ["nmcli", "dev", "wifi", "connect", ssid, "password", password];

	if (hidden)
		return ["nmcli", "dev", "wifi", "connect", ssid, "hidden", "yes"];

	return ["nmcli", "dev", "wifi", "connect", ssid];
}

function forgetCommand(name) {
	return ["nmcli", "connection", "delete", "id", name];
}

function disconnectCommand(device) {
	return ["nmcli", "device", "disconnect", device];
}

function radioCommand(state) {
	return ["nmcli", "radio", "wifi", state ? "on" : "off"];
}

function speedDownCommand(url, bytes) {
	return ["sh", "-c", "curl -o /dev/null -s -m " + 60 + " '" + url + "?bytes=" + Math.round(bytes) + "'"];
}

function speedUpCommand(url, bytes) {
	return ["sh", "-c", "head -c " + Math.round(bytes) + " /dev/zero | curl -o /dev/null -s -m 60 -X POST --data-binary @- '" + url + "'"];
}

function megaBits(bytesPerSecond) {
	return Math.max(0, Number(bytesPerSecond) || 0) * 8 / 1000000;
}

function speedText(bytesPerSecond) {
	return megaBits(bytesPerSecond).toFixed(0);
}

function speedCeiling(bytesPerSecond) {
	const ladder = [5, 10, 25, 50, 100, 250, 500, 1000];
	const mbps = megaBits(bytesPerSecond) * 1.5;

	for (let i = 0; i < ladder.length; i++)
		if (mbps < ladder[i])
			return ladder[i] * 125000;

	return ladder[ladder.length - 1] * 125000;
}

function scanCommand(device) {
	return ["nmcli", "--wait", "10", "device", "wifi", "rescan", "ifname", device];
}

function listCommand() {
	return ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,CHAN,FREQ,SECURITY,BSSID", "device", "wifi", "list"];
}
