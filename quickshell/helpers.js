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
