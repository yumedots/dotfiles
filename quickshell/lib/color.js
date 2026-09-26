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

function dangerColor(base, warn, danger, warnAt, dangerAt, pct) {
	if (pct <= warnAt)
		return mixColors(base, warn, warnAt > 0 ? pct / warnAt : 1);

	if (pct >= dangerAt)
		return mixColors(danger, danger, 1);

	return mixColors(warn, danger, dangerAt > warnAt ? (pct - warnAt) / (dangerAt - warnAt) : 1);
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
