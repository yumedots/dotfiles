import QtQuick
import qs
import qs.services

Item {
	id: root

	property real strength: 1

	function build() {
		const hues = [0.52, 0.85, 0.12];
		const out = [];

		for (let b = 0; b < hues.length; b++) {
			const points = [];

			for (let i = 0; i < 4; i++) {
				points.push({
					x: 0.25 + Math.random() * 0.5,
					y: 0.25 + Math.random() * 0.5,
					vx: (Math.random() - 0.5) * 0.014,
					vy: (Math.random() - 0.5) * 0.014
				});
			}

			const trail = [];

			for (let i = 0; i < 6; i++) trail.push(points.map(function (p) { return { x: p.x, y: p.y }; }));

			out.push({ points: points, hue: hues[b], trail: trail });
		}

		canvas.blobs = out;
	}

	function step() {
		for (const blob of canvas.blobs) {
			for (const point of blob.points) {
				point.x += point.vx;
				point.y += point.vy;

				if (point.x < 0) {
					point.x = 0;
					point.vx = Math.abs(point.vx);
				}

				if (point.x > 1) {
					point.x = 1;
					point.vx = -Math.abs(point.vx);
				}

				if (point.y < 0) {
					point.y = 0;
					point.vy = Math.abs(point.vy);
				}

				if (point.y > 1) {
					point.y = 1;
					point.vy = -Math.abs(point.vy);
				}
			}

			blob.trail.push(blob.points.map(function (p) { return { x: p.x, y: p.y }; }));

			if (blob.trail.length > 20)
				blob.trail.shift();
		}

		canvas.requestPaint();
	}

	Canvas {
		id: canvas

		anchors.fill: parent
		property var blobs: []

		onPaint: {
			const ctx = getContext("2d");

			ctx.clearRect(0, 0, width, height);
			ctx.lineWidth = 1.6;

			for (const blob of blobs) {
				for (let i = 0; i < blob.trail.length; i++) {
					const alpha = root.strength * ((i + 1) / blob.trail.length) * 0.7;
					const points = blob.trail[i];

					ctx.strokeStyle = "hsla(" + Math.round(blob.hue * 360) + ", 85%, 64%, " + alpha + ")";
					ctx.beginPath();
					ctx.moveTo(points[0].x * width, points[0].y * height);

					for (let k = 1; k < points.length; k++)
						ctx.lineTo(points[k].x * width, points[k].y * height);

					ctx.closePath();
					ctx.stroke();
				}
			}
		}
	}

	Timer {
		interval: 33
		running: true
		repeat: true
		onTriggered: root.step()
	}

	Component.onCompleted: {
		root.build();
		canvas.requestPaint();
	}
}
