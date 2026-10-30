import QtQuick
import qs

Canvas {
	id: root

	property int flow: 0
	property real watts: 0
	property real fill: 1
	property int rows: 8
	property color ink: Config.muted
	property color edgeInk: Config.dim
	property color hotInk: Config.powerBase

	property real phase: 0

	readonly property real pitch: root.height / root.rows
	readonly property real dot: root.pitch * 0.6
	readonly property int cols: Math.max(1, Math.floor(root.width / root.pitch))
	readonly property int span: 7

	onPhaseChanged: root.requestPaint()
	onFlowChanged: root.requestPaint()
	onFillChanged: root.requestPaint()
	onWidthChanged: root.requestPaint()
	onHeightChanged: root.requestPaint()

	Timer {
		interval: 40
		repeat: true
		running: root.visible && root.flow !== 0

		onTriggered: root.phase += interval / 1000 * (4 + Math.min(root.watts, 60) / 3)
	}

	function noise(a, b, c) {
		const h = Math.sin(a * 127.1 + b * 311.7 + c * 74.7) * 43758.5453;
		return h - Math.floor(h);
	}

	onPaint: {
		const ctx = getContext("2d");
		ctx.reset();

		const mid = (root.rows - 1) / 2;
		const amp = root.rows * 0.2;
		const drift = root.phase * 0.08 * root.flow;
		const tick = Math.floor(root.phase / 2);
		const run = root.cols + root.span * 2;
		const ahead = root.phase % run - root.span;
		const head = root.flow < 0 ? root.cols - 1 - ahead : ahead;
		const thick = 0.4 + 1.6 * Math.max(0, Math.min(1, root.fill));

		for (let x = 0; x < root.cols; x++) {
			const center = mid + amp * Math.sin(x * 0.32 + drift);
			const half = thick * (0.7 + 0.3 * Math.sin(x * 0.21 + 1.7));
			const near = root.flow === 0 ? 1 : Math.abs(x - head) / root.span;

			for (let r = 0; r < root.rows; r++) {
				const off = Math.abs(r - center);
				const core = off <= half;

				if (!core && !(off <= half + 1.2 && root.noise(x, r, tick) < 0.3))
					continue;

				const hot = near < 1 && root.noise(x, r, tick + 7) > near;

				ctx.fillStyle = hot ? root.hotInk : (core ? root.ink : root.edgeInk);
				ctx.beginPath();
				ctx.arc((x + 0.5) * root.pitch, (r + 0.5) * root.pitch, root.dot / 2, 0, Math.PI * 2);
				ctx.fill();
			}
		}
	}
}
