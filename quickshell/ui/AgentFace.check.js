const assert = require("assert");
const fs = require("fs");
const path = require("path");

const source = fs.readFileSync(path.join(__dirname, "AgentFace.qml"), "utf8");
const start = source.indexOf("readonly property real twoPi");
const functions = source
	.slice(start)
	.replace("readonly property real twoPi: Math.PI * 2;", "const twoPi = Math.PI * 2;")
	.replace(/\}\s*$/, "");

eval(functions);

const size = 44;
const width = size * 0.86;
const height = size * 0.86;
const margin = size * 0.02;

const sockets = [
	{ x: width / 2 - size * 0.22, y: height / 2 - size * 0.04, radiusX: size * 0.105, radiusY: size * 0.185 },
	{ x: width / 2 + size * 0.22, y: height / 2 - size * 0.04, radiusX: size * 0.105, radiusY: size * 0.185 },
];

// The same shape table the face draws from. The diamond is the shape the eyes
// have to be pulled in for, so a sweep that leaves it out proves nothing.
const shapes = {
	idle: { exponent: 2, lobes: 1, scallop: 0 },
	working: { exponent: 2, lobes: 9, scallop: 0.16 },
	blocked: { exponent: 2, lobes: 3, scallop: 0.28 },
	error: { exponent: 1, lobes: 1, scallop: 0 },
};

function bodyAt(samples, from, to, morph) {
	const spec = { width: width, height: height, samples: samples };

	return blendPoints(
		shapePoints(Object.assign({}, spec, shapes[from])),
		shapePoints(Object.assign({}, spec, shapes[to])),
		morph);
}

// What socketInside did before it walked the outline with a stride. The fit
// coarsens the outline to keep the panel face cheap, so the thing worth
// holding it to is the answer the full walk would have given.
function socketInsideWhole(outline, cx, cy, radiusX, radiusY, samples, gap) {
	const count = outline.length / 2;
	const edge = roundedRectPoints(cx, cy, radiusX - gap, radiusY - gap, Math.min(radiusX, radiusY) - gap, samples);

	for (let i = 0; i < edge.length; i += 2) {
		let inside = false;

		for (let j = 0, k = count - 1; j < count; k = j++) {
			const xi = outline[2 * j];
			const yi = outline[2 * j + 1];
			const xk = outline[2 * k];
			const yk = outline[2 * k + 1];

			if ((yi > edge[i + 1]) !== (yk > edge[i + 1])
				&& edge[i] < (xk - xi) * (edge[i + 1] - yi) / (yk - yi) + xi)
				inside = !inside;
		}

		if (!inside)
			return false;
	}

	return true;
}

function fitWhole(outline) {
	let low = 0;
	let high = 1;

	for (let i = 0; i < 12; i++) {
		const mid = (low + high) / 2;
		const ok = sockets.every(function (socket) {
			return socketInsideWhole(outline, socket.x, socket.y, socket.radiusX * mid, socket.radiusY * mid, 24, margin);
		});

		if (ok)
			low = mid;
		else
			high = mid;
	}

	return low;
}

// The coarsened walk has to land on the same eye the full walk would, through
// every morph between every pair of states, at any outline resolution.
const names = Object.keys(shapes);
let worst = 0;

for (const samples of [48, 96, 160, 320]) {
	for (const from of names) {
		for (const to of names) {
			for (let morph = 0; morph <= 1.0001; morph += 0.05) {
				const body = bodyAt(samples, from, to, morph);
				const fitted = clipSockets(body, sockets, margin);
				const reference = fitWhole(body);
				const where = `${from}->${to} samples=${samples} morph=${morph.toFixed(2)}`;

				for (let i = 0; i < fitted.length; i++) {
					assert.ok(fitted[i].radiusX > 0 && fitted[i].radiusY > 0, `eye vanished at ${where}`);

					const drift = Math.max(
						Math.abs(fitted[i].radiusX - sockets[i].radiusX * reference),
						Math.abs(fitted[i].radiusY - sockets[i].radiusY * reference));

					assert.ok(drift < 0.05, `eye drifted ${drift.toFixed(3)}px from the full-outline fit at ${where}`);
					worst = Math.max(worst, drift);
				}
			}
		}
	}
}

console.log(`AgentFace: eye fit holds, worst drift ${worst.toFixed(4)}px`);
