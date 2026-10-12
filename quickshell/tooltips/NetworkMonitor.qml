import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.ui
import qs.services

ProcessPanel {
	id: root

	property string stage: ""
	property real testDown: 0
	property real testUp: 0
	property real live: 0
	property real best: 0
	property real moved: 0
	property var testPrev: null
	property double started: 0

	readonly property var net: root.source
	readonly property color downInk: Util.pick(Config.mono, Config.networkDown, Config.networkDownMono)
	readonly property color upInk: Util.pick(Config.mono, Config.networkUp, Config.networkUpMono)
	readonly property string link: root.net && root.net.linked ? (root.net.ip !== "" ? root.net.ip : root.net.iface) : Config.networkWiredNothing
	readonly property bool testing: root.stage !== ""
	readonly property bool done: !root.testing && root.best > 0
	readonly property real hero: root.testing ? root.live : root.testDown
	readonly property real ceiling: Network.speedCeiling(root.testing ? root.best : root.testDown)
	readonly property color testInk: root.stage === "up" ? root.upInk : root.downInk
	readonly property string buttonText: root.testing
		? Config.networkSpeedCancelKey + " " + (root.stage === "down" ? Config.networkSpeedTestingDown : Config.networkSpeedTestingUp)
		: root.done ? "\u{2193} " + Network.speedText(root.testDown) + " \u{2191} " + Network.speedText(root.testUp) + " " + Config.networkSpeedAgain
			: Config.networkSpeedNone

	title: Config.networkTitle
	detail: root.net ? root.net.dev.connection : ""
	detailColor: root.downInk
	listInk: root.downInk
	totalInk: root.downInk
	showTotal: false
	showProcessList: false
	keyAction: (event) => Input.network(event, root)
	panelWidth: Config.networkTooltipWidth
	panelPadding: Config.networkTooltipPadding

	function graphValues(dir) {
		return (root.net ? root.net.history : []).map(function (point) {
			return dir === "up" ? point.up : point.down;
		});
	}

	function pushDots(out, masks, top, ink, cells, pitch, size) {
		for (let c = 0; c < cells; c++) {
			const mask = masks[c] || 0;

			for (let k = 0; k < 2; k++)
				for (let b = 0; b < 4; b++)
					if ((mask >> (k * 4 + b)) & 1)
						out.push({ x: Math.round((c * 2 + k + 0.5) * pitch - size / 2), y: Math.round((top + b + 0.5) * pitch - size / 2), c: ink });
		}
	}

	function graphDots(cells) {
		const out = [];
		const pitch = Config.networkGraphHeight / 8;
		const size = pitch * 0.76;
		const peak = root.scaleOf();

		pushDots(out, Network.brailleMasks(graphValues("up"), peak, cells, "up"), 0, root.upInk, cells, pitch, size);
		pushDots(out, Network.brailleMasks(graphValues("down"), peak, cells, "down"), 4, root.downInk, cells, pitch, size);

		return out;
	}

	function details() {
		const out = [];

		if (!root.net)
			return out;


		if (root.net.isWifi)
			out.push({ label: "signal", text: root.net.signal >= 0 ? root.net.signal + "%" : "—", color: root.upInk });

		out.push({ label: "ipv4", text: root.link, color: Config.foreground });

		if (root.net.info.gateway !== "")
			out.push({ label: "gateway", text: root.net.info.gateway, color: Config.foreground });

		if (root.net.info.dns !== "")
			out.push({ label: "dns", text: root.net.info.dns, color: Config.foreground });

		return out;
	}

	function scaleOf() {
		let top = 1;

		(root.net ? root.net.history : []).forEach(function (point) {
			top = Math.max(top, point.down, point.up);
		});

		return top;
	}

	function runTest() {
		if (root.testing)
			return;

		root.stage = "down";
		root.testDown = 0;
		root.testUp = 0;
		root.live = 0;
		root.best = 0;
		root.moved = 0;
		root.testPrev = null;
		root.started = Date.now();
		downTest.command = Network.speedDownCommand(Config.networkSpeedDownUrl, Config.networkSpeedBytes);
		downTest.reload();
		sampleTimer.restart();
		finishTimer.restart();
	}

	function primaryAction() {
		if (root.testing)
			root.cancelTest();
		else
			root.runTest();
	}

	function selectRun() {
		if (runButton.visible)
			runButton.forceActiveFocus();
	}

	function cancelTest() {
		if (!root.testing)
			return;

		sampleTimer.stop();
		finishTimer.stop();

		root.stage = "";
		root.live = 0;
		root.best = 0;
		root.moved = 0;
		root.testDown = 0;
		root.testUp = 0;
		root.testPrev = null;
	}

	function unselectRun() {
		runButton.focus = false;
		root.forceActiveFocus();
	}

	function finishUp() {
		root.stage = "up";
		root.live = 0;
		root.best = 0;
		root.moved = 0;
		root.testPrev = null;
		root.started = Date.now();
		upTest.command = Network.speedUpCommand(Config.networkSpeedUpUrl, Config.networkSpeedUpBytes);
		upTest.reload();
		sampleTimer.restart();
		finishTimer.restart();
	}

	function finish() {
		if (!root.testing)
			return;

		sampleTimer.stop();
		finishTimer.stop();

		if (root.stage === "down") {
			root.testDown = root.best;
			root.finishUp();
		} else {
			root.testUp = root.best;
			root.best = root.testDown;
			root.stage = "";
		}
	}

	function sample() {
		testFile.reload();
		root.read(testFile.text());
	}

	function read(text) {
		if (!root.testing || !root.net)
			return;

		const now = Date.now();
		const row = Network.parseRates(text)[root.net.iface];
		const bytes = row ? (root.stage === "down" ? row.rx : row.tx) : 0;

		if (root.testPrev && now > root.testPrev.at && bytes >= root.testPrev.bytes) {
			const delta = bytes - root.testPrev.bytes;

			if (delta > 0) {
				const inst = delta / ((now - root.testPrev.at) / 1000);

				root.moved += delta;
				root.live = root.live > 0 ? root.live + (inst - root.live) * 0.15 : inst;
				root.best = Math.max(root.best, root.live);
			}
		}

		root.testPrev = { at: now, bytes: bytes };
	}

	viz: [
		Item {
			width: parent.width
			height: Math.max(rateDown.implicitHeight, rateUp.implicitHeight)

			Text {
				id: rateDown

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.downInk
				text: "\u{2193} " + Network.rateText(root.net ? root.net.down : 0)
			}

			Text {
				id: rateUp

				anchors.left: rateDown.right
				anchors.leftMargin: Config.networkGraphGap * 3

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.upInk
				text: "\u{2191} " + Network.rateText(root.net ? root.net.up : 0)
			}
		},
		Item {
			id: graph
			width: parent.width
			height: Config.networkGraphHeight
			clip: true

			readonly property int cells: Math.max(4, Math.min(Config.networkHistory, Math.floor(width / (Config.networkGraphHeight / 4))))
			readonly property real dotPitch: Config.networkGraphHeight / 8

			Repeater {
				model: root.graphDots(graph.cells)

				delegate: Rectangle {
					required property var modelData

					x: modelData.x
					y: modelData.y
					width: Math.round(graph.dotPitch * 0.75)
					height: width
					radius: width / 2
					color: modelData.c
				}
			}
		},

		Repeater {
			model: root.details()

			delegate: Item {
				required property var modelData

				width: parent.width
				height: Math.max(detailLabel.implicitHeight, detailValue.implicitHeight)

				Text {
					id: detailLabel

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: modelData.color
					text: modelData.label
				}

				Text {
					id: detailValue

					anchors.right: parent.right
					width: parent.width - detailLabel.width - 8
					elide: Text.ElideRight
					horizontalAlignment: Text.AlignRight

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: modelData.color
					text: modelData.text
				}
			}
		},

		Item {
			width: parent.width
			height: Config.speedGaugeSize

			SpeedGauge {
				anchors.horizontalCenter: parent.horizontalCenter

				value: root.hero
				ceiling: root.ceiling
				ink: root.testInk
				valueText: Network.speedText(root.hero)
				arrow: root.stage === "down" ? "\u{2193}" : root.stage === "up" ? "\u{2191}" : ""
				arrowSide: root.stage === "up" ? "left" : "right"
			}
		},
		Rectangle {
			id: runButton

			width: Math.min(runLabel.implicitWidth + 2 * Config.speedButtonPadX, parent.width)
			height: runLabel.implicitHeight + 2 * Config.speedButtonPadY
			anchors.horizontalCenter: parent.horizontalCenter
			focus: true
			color: "transparent"
			radius: 0

			Highlight {
				anchors.fill: parent

				active: runButton.activeFocus || runHit.containsMouse
			}

			Text {
				id: runLabel

				anchors.centerIn: parent
				width: Math.min(implicitWidth, parent.width)

				elide: Text.ElideRight
				horizontalAlignment: Text.AlignHCenter

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: runButton.activeFocus || runHit.containsMouse ? Config.launcherHighlightText : root.done ? root.downInk : Config.foreground
				text: root.buttonText
			}

			MouseArea {
				id: runHit

				anchors.fill: parent
				hoverEnabled: true

				onClicked: root.primaryAction()
			}
		},

	]

	FileView {
		id: testFile

		path: "/proc/net/dev"
		blockLoading: true
	}

	Request {
		id: downTest

		function reload() {
			if (!downTest.running)
				downTest.running = true;
		}

		onRunningChanged: {
			if (downTest.running || root.stage !== "down")
				return;

			if (root.moved > 0 && Date.now() - root.started < Config.networkSpeedSeconds * 1000)
				downTest.reload();
			else
				root.finish();
		}
	}

	Request {
		id: upTest

		function reload() {
			if (!upTest.running)
				upTest.running = true;
		}

		onRunningChanged: {
			if (upTest.running || root.stage !== "up")
				return;

			if (root.moved > 0 && Date.now() - root.started < Config.networkSpeedSeconds * 1000)
				upTest.reload();
			else
				root.finish();
		}
	}

	Timer {
		id: sampleTimer

		interval: Config.networkSpeedSampleMs
		repeat: true
		running: root.testing
		onTriggered: root.sample()
	}

	Timer {
		id: finishTimer

		interval: Config.networkSpeedSeconds * 1000
		repeat: false
		running: false
		onTriggered: root.finish()
	}

	Connections {
		target: root.net

		function onTestPendingChanged() {
			if (root.net.testPending) {
				root.net.clearSpeedTest();
				root.runTest();
			}
		}
	}
}
