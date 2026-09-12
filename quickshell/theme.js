.pragma library

const background = "#000000";
const foreground = "#ffffff";
const dim = "#3f3f3f";
const red = "#e05252";
const muted = "#5c5c5c";

const workspaceActive = "#ffffff";
const workspaceInactive = "#5c5c5c";

const cpuBase = "#a78bfa";
const memoryBase = "#7bd88f";
const volumeBase = "#ffffff";

const fontFamily = "Hack Nerd Font";
const fontSize = 12;
const barHeight = 20;
const spacing = 12;
const sidePadding = 3;
const workspacePadding = 1;
const workspaceSpacing = 6;

const iconCpu = "\uf2db";
const iconMemory = "\uefc5";
const iconVolumeLow = "\uf026";
const iconVolumeMid = "\uf027";
const iconVolumeHigh = "\uf028";

const barCells = 15;
const lineLength = 45;
const barThickness = 1.5;

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

function filledCells(pct) {
	return Math.min(Math.max(Math.round((pct / 100) * barCells), 0), barCells);
}
