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
	property real progress: 0
	property var testPrev: null
	property double started: 0

	readonly property var net: root.source
	readonly property color downInk: Util.pick(Config.mono, Config.networkDown, Config.networkDownMono)
	readonly property color upInk: Util.pick(Config.mono, Config.networkUp, Config.networkUpMono)
	readonly property string link: root.net && root.net.linked ? (root.net.ip !== "" ? root.net.ip : root.net.iface) : Config.networkWiredNothing
	readonly property bool testing: root.stage !== ""
	readonly property bool done: !root.testing && root.best > 0
	readonly property bool showGauge: root.testing || root.done
	readonly property real hero: root.stage === "down" ? root.live : root.testDown
	readonly property real ceiling: Network.speedCeiling(root.stage === "down" ? root.best : root.testDown)
	readonly property color testInk: root.stage === "up" ? root.upInk : root.downInk
	readonly property string captionText: root.testing
		? (root.stage === "down" ? Config.networkSpeedTestingDown : Config.networkSpeedTestingUp)
		: (root.done ? Config.networkSpeedDoneLabel : "")
	readonly property string buttonText: root.done ? Config.networkSpeedAgain : Config.networkSpeedNone

	title: Config.networkTitle
	detail: root.net ? root.net.iface + " · " + root.net.dev.connection : ""
	detailColor: root.downInk
	listInk: root.downInk
	totalInk: root.downInk
	showTotal: false
	showProcessList: false
	panelWidth: Config.networkTooltipWidth
	panelPadding: Config.networkTooltipPadding

	function details() {
		const out = [];

		if (!root.net)
			return out;

		out.push({ label: "down", text: Network.rateText(root.net.down), color: root.downInk });
		out.push({ label: "up", text: Network.rateText(root.net.up), color: root.upInk });

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
		root.progress = 0;
		root.testPrev = null;
		root.started = Date.now();
		downTest.command = Network.speedDownCommand(Config.networkSpeedDownUrl, Config.networkSpeedBytes);
		downTest.reload();
		sampleTimer.restart();
		finishTimer.restart();
	}

	function finishUp() {
		root.stage = "up";
		root.live = 0;
		root.best = 0;
		root.progress = 0;
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
			const moved = bytes - root.testPrev.bytes;

			if (moved > 0) {
				const inst = moved / ((now - root.testPrev.at) / 1000);

				root.live = root.live > 0 ? root.live + (inst - root.live) * 0.5 : inst;
				root.best = Math.max(root.best, root.live);
			}
		}

		root.testPrev = { at: now, bytes: bytes };
		root.progress = Util.clamp((now - root.started) / 1000 / Config.networkSpeedSeconds, 0, 1);
	}

	viz: [
		Item {
			width: parent.width
			height: root.showGauge ? Config.speedGaugeSize + gaugeCaption.implicitHeight + 4 : runButton.height
			visible: root.showGauge

			SpeedGauge {
				anchors.horizontalCenter: parent.horizontalCenter

				value: root.hero
				ceiling: root.ceiling
				progress: root.testing ? root.progress : 0
				ink: root.testInk
				valueText: root.testing || root.done ? Network.speedText(root.hero) : Config.networkSpeedIdle
			}

			Text {
				id: gaugeCaption

				anchors.top: parent.top
				anchors.topMargin: Config.speedGaugeSize + 4
				anchors.horizontalCenter: parent.horizontalCenter

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.testInk
				text: root.captionText
			}
		},

		Rectangle {
			id: runButton

			width: runLabel.implicitWidth + 2 * Config.speedButtonPadX
			height: runLabel.implicitHeight + 2 * Config.speedButtonPadY
			anchors.horizontalCenter: parent.horizontalCenter
			visible: !root.testing
			color: "transparent"
			radius: height / 2
			border.width: 1
			border.color: root.done ? root.downInk : Config.foreground

			Text {
				id: runLabel

				anchors.centerIn: parent

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.done ? root.downInk : Config.foreground
				text: root.buttonText
			}

			MouseArea {
				anchors.fill: parent

				onClicked: root.runTest()
			}
		},

		Item {
			width: parent.width
			height: uploadLabel.implicitHeight
			visible: root.done

			Text {
				id: uploadLabel

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.upInk
				text: Config.networkSpeedUploadLabel
			}

			Text {
				anchors.right: parent.right

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.upInk
				text: Network.speedText(root.testUp) + " " + Config.networkSpeedUnit
			}
		},

		Item {
			width: parent.width
			height: Config.networkGraphHeight
			visible: !root.showGauge

			Repeater {
				model: root.net ? root.net.history : []

				delegate: Rectangle {
					required property var modelData
					required property int index

					property real peak: root.scaleOf()

					x: index * (Config.networkGraphGap + width)
					width: Math.max(1, (parent.width - (Config.networkHistory - 1) * Config.networkGraphGap) / Config.networkHistory)
					height: Math.max(1, parent.height * modelData.down / peak)
					anchors.bottom: parent.bottom
					color: root.downInk
					opacity: 0.9
				}
			}

			Repeater {
				model: root.net ? root.net.history : []

				delegate: Rectangle {
					required property var modelData
					required property int index

					property real peak: root.scaleOf()

					x: index * (Config.networkGraphGap + width)
					width: Math.max(1, (parent.width - (Config.networkHistory - 1) * Config.networkGraphGap) / Config.networkHistory)
					height: Math.max(1, parent.height * modelData.up / peak)
					anchors.top: parent.top
					color: root.upInk
					opacity: 0.6
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
		}
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

		onRunningChanged: if (!downTest.running && root.stage === "down") root.finish()
	}

	Request {
		id: upTest

		function reload() {
			if (!upTest.running)
				upTest.running = true;
		}

		onRunningChanged: if (!upTest.running && root.stage === "up") root.finish()
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
