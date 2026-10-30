import QtQuick
import QtQuick.Shapes
import qs
import qs.ui

// The agent face: a body shape that morphs with the agent state, and two eyes
// that blink.
//
// The eyes are holes in the body, so the background shows through them. The
// component scales to whatever size it is given, so the same face renders in
// the topbar as a small glyph and in the panel as a full size face.
Item {
	id: root

	// idle | working | blocked | error
	property string state: "idle"

	// Normalised direction from the face to the cursor, in [-1, 1] on both axes.
	property real gazeX: 0
	property real gazeY: 0

	// Whether the eyes follow the cursor. The topbar glyph keeps its eyes
	// still; only the panel face tracks the pointer.
	property bool followCursor: false

	property color bodyColor: Config.foreground
	property color eyeColor: Config.surface

	property real size: Config.agentFaceSize
	property bool paused: false

	// Small renders drop the breathing, so the bar glyph stays calm.
	readonly property bool small: root.size < 40

	// Shape per state. The vocabulary matches the workspace indicator's figure
	// table: a plain blob, a scalloped spike, a triangle, and a diamond.
	readonly property var shapes: ({
		idle: { exponent: 2, lobes: 1, scallop: 0 },
		working: { exponent: 2, lobes: 9, scallop: 0.16 },
		blocked: { exponent: 2, lobes: 3, scallop: 0.28 },
		error: { exponent: 1, lobes: 1, scallop: 0 },
	})

	readonly property var currentShape: shapes[state] || shapes.idle

	// The shape the morph starts from.
	property string fromState: "idle"
	property string lastState: "idle"
	property real morph: 1

	property real blink: 1
	property real breathe: 1

	property real openness: root.state === "working" ? 0 : (root.state === "blocked" ? 1.15 : 1)

	// The eyes close into a squint when the agent starts working instead of
	// snapping shut, and open again when it stops.
	Behavior on openness {
		enabled: !root.paused
		NumberAnimation {
			duration: 240
			easing.type: Easing.OutCubic
		}
	}
	readonly property real bodyWidth: root.size * 0.86
	readonly property real bodyHeight: root.size * 0.86

	// The body leans a little toward the cursor.
	readonly property real leanX: root.eyeX * root.size * 0.05
	readonly property real leanY: root.eyeY * root.size * 0.03

	// The spikes turn while the agent is working.
	property real spin: 0

	// Whether the face is on screen. A face that is not on screen does not
	// turn at all, so it costs nothing.
	property bool live: true

	// Whether the eyes are painted in the background instead of being holes
	// in the body. A face on a flat background paints them, so the body can
	// turn on its own; a face on a see-through background keeps them as
	// holes.
	property bool paintEyes: false

	readonly property bool spinning: root.state === "working" && !root.paused

	Timer {
		interval: 20
		repeat: true
		running: root.spinning

		onTriggered: root.spin = (root.spin + 360 * interval / Config.agentSpinMs) % 360
	}

	// The eyes only look around when they are told to.
	readonly property real lookX: root.followCursor ? root.gazeX : 0
	readonly property real lookY: root.followCursor ? root.gazeY : 0

	// The eyes glide toward where the pointer is instead of jumping there.
	property real eyeX: 0
	property real eyeY: 0

	Behavior on eyeX {
		enabled: !root.paused
		NumberAnimation {
			duration: 110
			easing.type: Easing.OutQuad
		}
	}

	Behavior on eyeY {
		enabled: !root.paused
		NumberAnimation {
			duration: 110
			easing.type: Easing.OutQuad
		}
	}

	onLookXChanged: root.eyeX = root.lookX
	onLookYChanged: root.eyeY = root.lookY

	// The eyes are spaced so they never merge, at any size, and stay well
	// inside the body even when they look to the side.
	//
	// An eye is taller than it is wide, so it reads as a pill rather than a
	// dot.
	readonly property real eyeSpacing: root.size * 0.22
	readonly property real eyeRadius: root.size * 0.185
	readonly property real eyeWidth: root.size * 0.105
	readonly property real eyeLift: root.size * 0.04

	// How much room the eye keeps from the edge of the body, so it never
	// touches the rim and flattens the outline into a notch.
	readonly property real eyeMargin: root.size * 0.02

	// How far the eyes travel toward the cursor.
	readonly property real eyeTravel: root.size * 0.055

	// The eye sockets, in body-local coordinates. They are holes in the body,
	// and they slide toward the cursor so the face looks where the pointer is.
	// The socket squashes vertically as the eye closes, so a blink flattens the
	// eye into a line.
	//
	// The fit only changes when the body or a blink does, so the pointer moving
	// costs a few comparisons instead of a hit test.
	readonly property var fittedSockets: {
		// A closed eye keeps a little thickness, so it reads as a shut eye
		// instead of a scratch.
		const squish = Math.max(0.3, Math.min(1, root.openness * root.blink));

		return clipSockets(root.body, [
			{ x: root.bodyWidth / 2 - root.eyeSpacing, y: root.bodyHeight / 2 - root.eyeLift, radiusX: root.eyeWidth, radiusY: root.eyeRadius * squish },
			{ x: root.bodyWidth / 2 + root.eyeSpacing, y: root.bodyHeight / 2 - root.eyeLift, radiusX: root.eyeWidth, radiusY: root.eyeRadius * squish },
		], root.eyeMargin);
	}

	readonly property var sockets: {
		const slide = clampShift(root.body, root.fittedSockets, root.eyeX * root.eyeTravel, root.eyeY * root.eyeTravel, root.eyeMargin);

		return root.fittedSockets.map(function (socket) {
			return { x: socket.x + slide.x, y: socket.y + slide.y, radiusX: socket.radiusX, radiusY: socket.radiusY };
		});
	}

	// The eyes, as paths. They are holes in the body.
	//
	// An eye is a rectangle with round corners, and the corner radius is half
	// the short side, so the ends are circles.
	readonly property var eyePaths: root.sockets.map(function (socket) {
		const radius = Math.min(socket.radiusX, socket.radiusY);

		return roundedRectPoints(socket.x, socket.y, socket.radiusX, socket.radiusY, radius, 40);
	})

	onStateChanged: {
		root.fromState = root.lastState;
		root.lastState = root.state;
		root.morph = 0;
		morphAnimation.restart();
	}

	SequentialAnimation {
		id: morphAnimation

		NumberAnimation {
			target: root
			property: "morph"
			to: 1
			duration: Config.agentMorphMs
			easing.type: Easing.OutCubic
		}
	}

	// Blinking. Working keeps the eyes shut, so the timer only drives the
	// other states.
	Timer {
		interval: 2600
		repeat: true
		running: !root.paused && root.state !== "working"

		onTriggered: blinkSequence.restart()
	}

	SequentialAnimation {
		id: blinkSequence

		NumberAnimation {
			target: root
			property: "blink"
			to: 0
			duration: 70
			easing.type: Easing.InQuad
		}

		NumberAnimation {
			target: root
			property: "blink"
			to: 1
			duration: 260
			easing.type: Easing.OutCubic
		}
	}

	// Breathing. It is a scale on the body rather than part of the outline, so
	// the geometry is only rebuilt while the body is morphing.
	SequentialAnimation {
		loops: Animation.Infinite
		running: !root.paused && !root.small

		NumberAnimation {
			target: root
			property: "breathe"
			from: 1
			to: 0.985
			duration: 1900
			easing.type: Easing.InOutSine
		}

		NumberAnimation {
			target: root
			property: "breathe"
			from: 0.985
			to: 1
			duration: 1900
			easing.type: Easing.InOutSine
		}
	}

	// The body outline, before it is turned. The eyes are placed against this,
	// so they stay level while the spikes turn.
	readonly property var body: {
		const spec = root.shapes[root.fromState] || root.shapes.idle;
		const from = shapePoints({
			width: root.bodyWidth,
			height: root.bodyHeight,
			exponent: spec.exponent,
			lobes: spec.lobes,
			scallop: spec.scallop,
			samples: root.small ? 48 : 160,
		});

		const to = shapePoints({
			width: root.bodyWidth,
			height: root.bodyHeight,
			exponent: root.currentShape.exponent,
			lobes: root.currentShape.lobes,
			scallop: root.currentShape.scallop,
			samples: root.small ? 48 : 160,
		});

		return blendPoints(from, to, root.morph);
	}

	// The outline of the body, with the spikes turned on it. The eyes are
	// holes in the body, so the body is turned on its own and the eyes stay
	// where they are.
	readonly property var outline: {
		if (!root.live)
			return root.body;

		return rotatePoints(root.body, root.bodyWidth / 2, root.bodyHeight / 2, root.spin);
	}

	// The icon is drawn in body-local space, so it moves with the body.
	Item {
		id: body

		x: (root.width - root.bodyWidth) / 2 + root.leanX
		y: (root.height - root.bodyHeight) / 2 + root.leanY
		width: root.bodyWidth
		height: root.bodyHeight

		// The body leans toward the cursor.
		rotation: root.eyeX * 4

		scale: root.breathe
		transformOrigin: Item.Center

		// The body and the eyes are one path, so the eyes are holes in the
		// body.
		DynamicIcon {
			anchors.fill: parent

			ink: root.bodyColor

			subpaths: root.paintEyes ? [root.outline] : [root.outline].concat(root.eyePaths)
		}

		// A face that is drawn on a flat background paints its eyes in that
		// background, so the body can turn on its own and the eyes stay
		// level. A face on a see-through background keeps them as holes.
		DynamicIcon {
			anchors.fill: parent

			visible: root.paintEyes

			ink: root.eyeColor

			subpaths: root.eyePaths
		}
	}

readonly property real twoPi: Math.PI * 2;

function superellipseRadius(angle, exponent) {
	const cos = Math.abs(Math.cos(angle));
	const sin = Math.abs(Math.sin(angle));

	return Math.pow(Math.pow(cos, exponent) + Math.pow(sin, exponent), -1 / exponent);
}

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
		const angle = fraction * twoPi - Math.PI / 2;
		const radius = superellipseRadius(angle, exponent);
		const phase = ((fraction * lobes) + 0.5) % 1;
		const wave = 1 - depth * (0.5 - 0.5 * Math.cos(twoPi * phase));

		points.push(cx + radius * Math.cos(angle) * cx * wave, cy + radius * Math.sin(angle) * cy * wave);
	}

	return points;
}

function blendPoints(from, to, progress) {
	const amount = Math.max(0, Math.min(1, progress));
	const points = new Array(from.length);

	for (let i = 0; i < from.length; i++)
		points[i] = from[i] + (to[i] - from[i]) * amount;

	return points;
}

function rotatePoints(points, cx, cy, angle) {
	if (!angle)
		return points;

	const cos = Math.cos(angle);
	const sin = Math.sin(angle);
	const out = new Array(points.length);

	for (let i = 0; i < points.length; i += 2) {
		const x = points[i] - cx;
		const y = points[i + 1] - cy;

		out[i] = cx + x * cos - y * sin;
		out[i + 1] = cy + x * sin + y * cos;
	}

	return out;
}

function ellipsePoints(cx, cy, radiusX, radiusY, samples) {
	const count = Math.max(12, Math.round(samples || 24));
	const points = [];

	for (let i = 0; i < count; i++) {
		const angle = (i / count) * twoPi;
		points.push(cx + Math.cos(angle) * radiusX, cy + Math.sin(angle) * radiusY);
	}

	return points;
}

function roundedRectPoints(cx, cy, halfWidth, halfHeight, radius, samples) {
	const count = Math.max(2, Math.round((samples || 40) / 4));
	const r = Math.min(radius, Math.min(halfWidth, halfHeight));
	const points = [];
	const corners = [
		[cx + halfWidth - r, cy - halfHeight + r, -Math.PI / 2],
		[cx + halfWidth - r, cy + halfHeight - r, 0],
		[cx - halfWidth + r, cy + halfHeight - r, Math.PI / 2],
		[cx - halfWidth + r, cy - halfHeight + r, Math.PI],
	];

	for (let i = 0; i < corners.length; i++) {
		const corner = corners[i];

		for (let j = 0; j <= count; j++) {
			const angle = corner[2] + (j / count) * (Math.PI / 2);

			points.push(corner[0] + Math.cos(angle) * r, corner[1] + Math.sin(angle) * r);
		}
	}

	return points;
}

function clipSockets(outline, sockets, margin) {
	const inside = function (socket, factor) {
		return socketInside(outline, socket.x, socket.y, socket.radiusX * factor, socket.radiusY * factor, 24, margin || 0);
	};

	let low = 0;
	let high = 1;

	for (let i = 0; i < 12; i++) {
		const mid = (low + high) / 2;

		if (sockets.every(function (socket) { return inside(socket, mid); }))
			low = mid;
		else
			high = mid;
	}

	return sockets.map(function (socket) {
		return {
			x: socket.x,
			y: socket.y,
			radiusX: socket.radiusX * low,
			radiusY: socket.radiusY * low
		};
	});
}

function socketInside(outline, cx, cy, radiusX, radiusY, samples, margin) {
	const total = outline.length / 2;

	// The fit only sets how big an eye may grow, so it is tested against a
	// coarser copy of the outline. Dropping points pulls the test shape inside
	// the real one, so the eye it allows still fits.
	const stride = Math.max(1, Math.floor(total / 48));
	const count = Math.floor(total / stride);

	const gap = margin || 0;
	const edge = roundedRectPoints(cx, cy, radiusX - gap, radiusY - gap, Math.min(radiusX, radiusY) - gap, samples || 24);

	for (let i = 0; i < edge.length; i += 2) {
		const x = edge[i];
		const y = edge[i + 1];

		let insidePoint = false;

		for (let j = 0, k = count - 1; j < count; k = j++) {
			const xi = outline[2 * j * stride];
			const yi = outline[2 * j * stride + 1];
			const xk = outline[2 * k * stride];
			const yk = outline[2 * k * stride + 1];

			if ((yi > y) !== (yk > y) && x < (xk - xi) * (y - yi) / (yk - yi) + xi)
				insidePoint = !insidePoint;
		}

		if (!insidePoint)
			return false;
	}

	return true;
}

function clampShift(outline, sockets, dx, dy, margin) {
	const fits = function (t) {
		for (let i = 0; i < sockets.length; i++) {
			const socket = sockets[i];

			if (!socketInside(outline, socket.x + dx * t, socket.y + dy * t, socket.radiusX, socket.radiusY, 8, margin || 0))
				return false;
		}

		return true;
	};

	let low = 0;
	let high = 1;

	for (let i = 0; i < 8; i++) {
		const mid = (low + high) / 2;

		if (fits(mid))
			low = mid;
		else
			high = mid;
	}

	return { x: dx * low, y: dy * low };
}


}
