import QtQuick
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
	property var samples: []
	property double at: 0
	property double started: 0

	readonly property var net: root.source
	readonly property color downInk: Util.pick(Config.mono, Config.networkDown, Config.networkDownMono)
	readonly property color upInk: Util.pick(Config.mono, Config.networkUp, Config.networkUpMono)
	readonly property string link: root.net && root.net.linked ? (root.net.ip !== "" ? root.net.ip : root.net.iface) : Config.networkWiredNothing
	readonly property bool testing: root.stage !== ""
	readonly property bool done: !root.testing && root.best > 0

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
		root.samples = [];
		root.started = Date.now();
		root.at = root.started;
		downTest.command = Network.speedDownCommand(Config.networkSpeedDownUrl, Config.networkSpeedBytes);
		downTest.reload();
		sampleTimer.restart();
		finishTimer.restart();
	}

	function finishUp() {
		root.stage = "up";
		root.live = 0;
		root.progress = 0;
		root.samples = [];
		root.started = Date.now();
		root.at = root.started;
		upTest.command = Network.speedUpCommand(Config.networkSpeedUpUrl, Config.networkSpeedUpBytes);
		upTest.reload();
		sampleTimer.restart();
		finishTimer.restart();
	}

	function finish() {
		sampleTimer.stop();
		finishTimer.stop();

		if (!root.testing)
			return;

		if (root.stage === "down") {
			root.testDown = root.best;
			root.finishUp();
		} else {
			root.testUp = root.best;
			root.stage = "";
		}
	}

	function sample() {
		if (!root.testing || !root.net)
			return;

		const now = Date.now();
		const secs = (now - root.at) / 1000;

		root.at = now;

		if (root.stage === "down")
			root.samples = root.samples.concat([{ at: now, bytes: root.net.counts[root.net.iface] ? root.net.counts[root.net.iface].rx : 0 }]);
		else
			root.samples = root.samples.concat([{ at: now, bytes: root.net.counts[root.net.iface] ? root.net.counts[root.net.iface].tx : 0 }]);

		if (root.samples.length < 3)
			return;

		const recent = root.samples.filter(function (point) {
			return now - point.at <= Config.networkSpeedSampleMs * 2;
		});

		if (recent.length < 2)
			return;

		const span = (recent[recent.length - 1].at - recent[0].at) / 1000;
		const moved = recent[recent.length - 1].bytes - recent[0].bytes;

		if (span > 0 && moved >= 0) {
			root.live = moved / span;
			root.best = Math.max(root.best, root.live);
		}

		root.progress = Util.clamp((now - root.started) / 1000 / Config.networkSpeedSeconds, 0, 1);
	}

	viz: [
		Item {
			width: parent.width
			height: Config.networkGraphHeight

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
		},

		Text {
			width: parent.width
			horizontalAlignment: Text.AlignHCenter

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: root.testing ? root.downInk : Config.foreground
			text: root.testing ? Config.networkSpeedRunning : (root.done ? "" : Config.networkSpeedNone)

			MouseArea {
				anchors.fill: parent
				enabled: !root.testing

				onClicked: root.runTest()
			}
		},

		Item {
			width: parent.width
			height: speedValue.implicitHeight
			visible: root.testing || root.done

			Text {
				id: speedValue

				anchors.left: parent.left

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.stage === "up" ? root.upInk : root.downInk
				text: Network.speedText(root.testing ? root.live : root.testDown)
			}

			Text {
				anchors.right: parent.right

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.stage === "up" ? root.upInk : root.downInk
				text: Config.networkSpeedUnit + (root.stage === "up" ? " ↑" : " ↓")
			}
		},

		Item {
			width: parent.width
			height: Config.speedBarHeight
			visible: root.testing || root.done

			Rectangle {
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				height: 1
				color: Config.networkIdle
			}

			Rectangle {
				anchors.left: parent.left
				anchors.top: parent.top
				anchors.bottom: parent.bottom
				width: parent.width * root.progress
				color: root.stage === "up" ? root.upInk : root.downInk
				opacity: 0.5
			}
		},

		Text {
			width: parent.width
			visible: root.done

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: Config.foreground
			text: Network.speedText(root.testDown) + " ↓ / " + Network.speedText(root.testUp) + " ↑ " + Config.networkSpeedUnit
		}
	]

	Request {
		id: downTest

		function reload() {
			if (!downTest.running)
				downTest.running = true;
		}
	}

	Request {
		id: upTest

		function reload() {
			if (!upTest.running)
				upTest.running = true;
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
}
