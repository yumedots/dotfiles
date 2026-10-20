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
	readonly property real leanX: root.lookX * root.size * 0.05
	readonly property real leanY: root.lookY * root.size * 0.03

	// The eyes only look around when they are told to.
	readonly property real lookX: root.followCursor ? root.gazeX : 0
	readonly property real lookY: root.followCursor ? root.gazeY : 0

	// The eyes are spaced so they never merge, at any size.
	readonly property real eyeSpacing: root.size * 0.24
	readonly property real eyeRadius: root.size * 0.15
	readonly property real eyeLift: root.size * 0.04

	// How far the eyes travel toward the cursor.
	readonly property real eyeTravel: root.size * 0.06

	// The eye sockets, in body-local coordinates. They are holes in the body,
	// and they slide toward the cursor so the face looks where the pointer is.
	// The socket squashes vertically as the eye closes, so a blink flattens the
	// eye into a line.
	readonly property var sockets: {
		const squish = Math.max(0.08, Math.min(1, root.openness * root.blink));
		const cy = root.bodyHeight / 2 - root.eyeLift + root.lookY * root.eyeTravel;
		const shift = root.lookX * root.eyeTravel;

		return [
			{ x: root.bodyWidth / 2 - root.eyeSpacing + shift, y: cy, radiusX: root.eyeRadius, radiusY: root.eyeRadius * squish },
			{ x: root.bodyWidth / 2 + root.eyeSpacing + shift, y: cy, radiusX: root.eyeRadius, radiusY: root.eyeRadius * squish },
		];
	}

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

	readonly property var outline: {
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

	// The icon is drawn in body-local space, so it moves with the body.
	Item {
		id: body

		x: (root.width - root.bodyWidth) / 2 + root.leanX
		y: (root.height - root.bodyHeight) / 2 + root.leanY
		width: root.bodyWidth
		height: root.bodyHeight

		rotation: root.lookX * 4

		scale: root.breathe
		transformOrigin: Item.Center

		DynamicIcon {
			anchors.fill: parent

			ink: root.bodyColor

			subpaths: [root.outline].concat(root.sockets.map(function (socket) {
				return Agent.ellipsePoints(socket.x, socket.y, socket.radiusX, socket.radiusY, 40);
			}))
		}
	}
}
