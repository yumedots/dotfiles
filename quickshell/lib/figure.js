.pragma library

const figurePresets = {
	squircle: { exponent: 4 },
	circle: { exponent: 2 },
	gear: { exponent: 2 },
	square: { exponent: 8 }
};

const coarseSteps = 512;

function figurePreset(name) {
	return figurePresets[name] || figurePresets.squircle;
}

function outline(width, height, exponent, steps) {
	const cx = width / 2;
	const cy = height / 2;
	const points = [];

	for (let i = 0; i < steps; i++) {
		const angle = (i / steps) * Math.PI * 2 - Math.PI / 2;
		const cos = Math.cos(angle);
		const sin = Math.sin(angle);
		const radius = Math.pow(Math.pow(Math.abs(cos), exponent) + Math.pow(Math.abs(sin), exponent), -1 / exponent);

		points.push(cx + radius * cos * cx);
		points.push(cy + radius * sin * cy);
	}

	return points;
}

function figurePoints(spec) {
	const width = spec.width;
	const height = spec.height;
	const exponent = spec.exponent || 4;
	const lobes = Math.max(1, Math.round(spec.lobes || 8));
	const scallop = Math.min(0.9, Math.max(0, spec.scallop === undefined ? 0.16 : spec.scallop));
	const morph = Math.max(0, spec.morph === undefined ? 0 : spec.morph);
	const flank = Math.min(0.24, Math.max(0.02, spec.flank === undefined ? 0.1 : spec.flank));
	const samples = Math.max(lobes * 3, Math.round(spec.samples || lobes * 12));
	const cx = width / 2;
	const cy = height / 2;
	const depth = Math.min(0.9, scallop * morph);
	const base = outline(width, height, exponent, coarseSteps);
	const lengths = [0];

	for (let i = 0; i < coarseSteps; i++) {
		const next = (i + 1) % coarseSteps;

		lengths.push(lengths[i] + Math.hypot(base[2 * next] - base[2 * i], base[2 * next + 1] - base[2 * i + 1]));
	}

	const perimeter = lengths[coarseSteps];
	const points = [];
	let segment = 0;

	for (let i = 0; i < samples; i++) {
		const at = (i / samples) * perimeter;

		while (segment < coarseSteps - 1 && lengths[segment + 1] < at)
			segment++;

		const span = lengths[segment + 1] - lengths[segment];
		const part = span > 0 ? (at - lengths[segment]) / span : 0;
		const from = 2 * segment;
		const to = 2 * ((segment + 1) % coarseSteps);
		const phase = ((i / samples) * lobes + 0.5) % 1;
		const away = Math.abs(phase - 0.5);
		const tooth = away <= 0.2 ? 1 : away <= 0.2 + flank ? 1 - (away - 0.2) / flank : 0;
		const wave = 1 - depth * tooth;
		const x = base[from] + (base[to] - base[from]) * part;
		const y = base[from + 1] + (base[to + 1] - base[from + 1]) * part;

		points.push(cx + (x - cx) * wave);
		points.push(cy + (y - cy) * wave);
	}

	return points;
}
