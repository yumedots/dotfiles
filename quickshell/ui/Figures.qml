import QtQuick
import QtQuick.Shapes
import qs

Shape {
	id: root

	property int version: 1
	property real morph: 0
	property real exponent: root.shape.exponent
	property color color: Config.foreground

	preferredRendererType: Shape.CurveRenderer
	asynchronous: false

	readonly property var shape: figureShape(root.version)
	readonly property var outline: figurePoints({
		width: root.width,
		height: root.height,
		exponent: root.exponent,
		lobes: root.shape.lobes === undefined ? Config.figureLobes : root.shape.lobes,
		scallop: root.shape.scallop === undefined ? Config.figureScallop : root.shape.scallop,
		morph: root.morph
	})

	ShapePath {
		strokeColor: "transparent"
		fillColor: root.color

		PathPolyline {
			path: {
				const list = [];

				for (let i = 0; i < root.outline.length; i += 2)
					list.push(Qt.point(root.outline[i], root.outline[i + 1]));

				return list;
			}
		}
	}

const figureShapes = [
	{ exponent: 4 },
	{ exponent: 2, lobes: 9, scallop: 0.16 },
	{ exponent: 2, lobes: 3, scallop: 0.28 },
	{ exponent: 2, lobes: 4, scallop: 0.28 },
	{ exponent: 2, lobes: 5, scallop: 0.45 },
	{ exponent: 8, scallop: 0 },
	{ exponent: 1.4, scallop: 0 },
	{ exponent: 8, lobes: 4, scallop: 0.45 },
	{ exponent: 1, scallop: 0 },
	{ exponent: 8, lobes: 8, scallop: 0.12 }
];

const coarseSteps = 512;

function figureShape(version) {
	return figureShapes[Math.round(version) - 1] || figureShapes[0];
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
		const wave = 1 - depth * (0.5 - 0.5 * Math.cos(2 * Math.PI * phase));
		const x = base[from] + (base[to] - base[from]) * part;
		const y = base[from + 1] + (base[to + 1] - base[from + 1]) * part;

		points.push(cx + (x - cx) * wave);
		points.push(cy + (y - cy) * wave);
	}

	return points;
}
}
