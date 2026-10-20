.pragma library

// Geometry for the agent face.
//
// The body reuses the workspace indicator's shape vocabulary (superellipse +
// scalloped lobes) but samples by angle instead of by perimeter, so the lobe
// count can be fractional and two states can be interpolated point for point.
//
// See lib/figure.js for the shape table the workspace indicator uses.

const TWO_PI = Math.PI * 2;

function superellipseRadius(angle, exponent) {
	const cos = Math.abs(Math.cos(angle));
	const sin = Math.abs(Math.sin(angle));

	return Math.pow(Math.pow(cos, exponent) + Math.pow(sin, exponent), -1 / exponent);
}

// Outline points for one shape, sampled by angle. Returns a flat [x, y, ...]
// array so it can feed PathPolyline directly.
function shapePoints(spec) {
	const width = Math.max(1, spec.width || 1);
	const height = Math.max(1, spec.height || 1);
	const exponent = spec.exponent || 2;
	const lobes = Math.max(0.5, spec.lobes || 1);
	const scallop = Math.min(0.9, Math.max(0, spec.scallop === undefined ? 0 : spec.scallop));
	const depth = Math.min(0.9, scallop * (spec.morph === undefined ? 1 : spec.morph));
	const samples = Math.max(24, Math.round(spec.samples || 128));
	const cx = width / 2;
	const cy = height / 2;
	const points = [];

	for (let i = 0; i < samples; i++) {
		const fraction = i / samples;
		const angle = fraction * TWO_PI - Math.PI / 2;
		const radius = superellipseRadius(angle, exponent);
		const phase = ((fraction * lobes) + 0.5) % 1;
		const wave = 1 - depth * (0.5 - 0.5 * Math.cos(TWO_PI * phase));

		points.push(cx + radius * Math.cos(angle) * cx * wave, cy + radius * Math.sin(angle) * cy * wave);
	}

	return points;
}

// Blend two outlines that were produced by shapePoints.
function blendPoints(from, to, progress) {
	const amount = Math.max(0, Math.min(1, progress));
	const points = new Array(from.length);

	for (let i = 0; i < from.length; i++)
		points[i] = from[i] + (to[i] - from[i]) * amount;

	return points;
}

// Circle outline, used for the pupil.
function circlePoints(cx, cy, radius, samples) {
	const count = Math.max(12, Math.round(samples || 24));
	const points = [];

	for (let i = 0; i < count; i++) {
		const angle = (i / count) * TWO_PI;
		points.push(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius);
	}

	return points;
}

// Ellipse outline, used for the eye sockets. A socket squashes vertically as
// the eye closes, so a blink flattens the eye into a line.
function ellipsePoints(cx, cy, radiusX, radiusY, samples) {
	const count = Math.max(12, Math.round(samples || 24));
	const points = [];

	for (let i = 0; i < count; i++) {
		const angle = (i / count) * TWO_PI;
		points.push(cx + Math.cos(angle) * radiusX, cy + Math.sin(angle) * radiusY);
	}

	return points;
}

// The session the input line sends to: the agent that is working wins, or
// else the one that was touched last. A session that was only listed is not
// activity, so it never beats a session that was.
function pickTarget(sessions) {
	const ids = Object.keys(sessions || {});
	let best = "";
	let bestStamp = -1;
	let working = "";
	let workingStamp = -1;

	for (let i = 0; i < ids.length; i++) {
		const id = ids[i];
		const session = sessions[id] || {};
		const stamp = session.updated || 0;

		if (stamp > bestStamp) {
			bestStamp = stamp;
			best = id;
		}

		if ((session.status === "busy" || session.status === "retry") && stamp > workingStamp) {
			workingStamp = stamp;
			working = id;
		}
	}

	return working || best;
}

// The path of the fifo the cursor plugin writes to.
//
// The fifo lives in the Hyprland instance's own directory, so a nested test
// session gets its own stream instead of competing with the live one for the
// same fifo. Two readers on one fifo each get an arbitrary share of the frames.
function cursorFifoPath(env) {
	const runtime = (env && env.XDG_RUNTIME_DIR) || "/tmp";
	const signature = (env && env.HYPRLAND_INSTANCE_SIGNATURE) || "";

	if (!signature)
		return runtime + "/agent-cursor.fifo";

	return runtime + "/hypr/" + signature + "/agent-cursor.fifo";
}

