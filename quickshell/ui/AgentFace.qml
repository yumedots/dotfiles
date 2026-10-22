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

	readonly property real openness: root.state === "working" ? 0 : (root.state === "blocked" ? 1.15 : 1)
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

	RotationAnimation on spin {
		from: 0
		to: 360
		duration: Config.agentSpinMs
		running: root.spinning
		loops: Animation.Infinite
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
			duration: 260
			easing.type: Easing.OutCubic
		}
	}

	Behavior on eyeY {
		enabled: !root.paused
		NumberAnimation {
			duration: 260
			easing.type: Easing.OutCubic
		}
	}

	onLookXChanged: root.eyeX = root.lookX
	onLookYChanged: root.eyeY = root.lookY

	// The eyes are spaced so they never merge, at any size, and stay well
	// inside the body even when they look to the side.
	readonly property real eyeSpacing: root.size * 0.235
	readonly property real eyeRadius: root.size * 0.13
	readonly property real eyeLift: root.size * 0.04

	// How far the eyes travel toward the cursor.
	readonly property real eyeTravel: root.size * 0.05

	// The eye sockets, in body-local coordinates. They are holes in the body,
	// and they slide toward the cursor so the face looks where the pointer is.
	// The socket squashes vertically as the eye closes, so a blink flattens the
	// eye into a line.
	readonly property var sockets: {
		// A closed eye keeps a little thickness, so it reads as a shut eye
		// instead of a scratch.
		const squish = Math.max(0.2, Math.min(1, root.openness * root.blink));
		const cy = root.bodyHeight / 2 - root.eyeLift + root.eyeY * root.eyeTravel;
		const shift = root.eyeX * root.eyeTravel;

		// A closed eye is a short line, not a wide flat slot, so it stays inside
		// the body and reads as a shut eye rather than a scratch.
		const radiusX = root.eyeRadius * (0.55 + 0.45 * squish);

		const wanted = [
			{ x: root.bodyWidth / 2 - root.eyeSpacing + shift, y: cy, radiusX: radiusX, radiusY: root.eyeRadius * squish },
			{ x: root.bodyWidth / 2 + root.eyeSpacing + shift, y: cy, radiusX: radiusX, radiusY: root.eyeRadius * squish },
		];

		// An eye that runs past the edge of the body would turn inside out, so
		// the sockets are pulled back until they fit. Both shrink the same
		// amount, so the eyes stay the same size.
		return Agent.clipSockets(root.body, wanted);
	}

	// The eyes, as paths. They are holes in the body.
	readonly property var eyePaths: root.sockets.map(function (socket) {
		return Agent.ellipsePoints(socket.x, socket.y, socket.radiusX, socket.radiusY, 40);
	})

	onStateChanged: {
		root.fromState = root.lastState;
		root.lastState = root.state;
		root.morph = 0;
		root.spin = 0;
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
			duration: 110
			easing.type: Easing.OutQuad
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
		const from = Agent.shapePoints({
			width: root.bodyWidth,
			height: root.bodyHeight,
			exponent: spec.exponent,
			lobes: spec.lobes,
			scallop: spec.scallop,
			samples: root.small ? 48 : 160,
		});

		const to = Agent.shapePoints({
			width: root.bodyWidth,
			height: root.bodyHeight,
			exponent: root.currentShape.exponent,
			lobes: root.currentShape.lobes,
			scallop: root.currentShape.scallop,
			samples: root.small ? 48 : 160,
		});

		return Agent.blendPoints(from, to, root.morph);
	}

	// The outline of the body, with the spikes turned on it. The eyes are
	// holes in the body, so the body is turned on its own and the eyes stay
	// where they are.
	readonly property var outline: {
		if (!root.live)
			return root.body;

		return Agent.rotatePoints(root.body, root.bodyWidth / 2, root.bodyHeight / 2, root.spin);
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
}
