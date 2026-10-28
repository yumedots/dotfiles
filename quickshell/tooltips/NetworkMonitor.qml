import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.ui
import qs.services

ProcessPanel {
	id: root

	property bool dnsFocus: false
	property bool dnsEditing: false
	property string dnsCustom: ""
	property string wifiTarget: ""
	property string wifiPassword: ""

	readonly property var net: Yudae.network
	readonly property var speed: root.net.speed || ({})
	readonly property var wifi: root.net.wifi || []
	readonly property var history: root.net.history || []
	readonly property string connection: root.net.ssid || root.net.iface || ""
	readonly property string dns: root.net.dns || ""
	readonly property bool linked: root.net.connected === true
	readonly property bool isWifi: root.net.kind === "wifi"
	readonly property color downInk: Util.pick(Config.mono, Config.networkDown, Config.networkDownMono)
	readonly property color upInk: Util.pick(Config.mono, Config.networkUp, Config.networkUpMono)
	readonly property string link: root.linked ? (root.net.ip !== "" ? root.net.ip : root.net.iface) : Config.networkWiredNothing
	readonly property bool testing: (root.speed.stage || "") !== ""
	readonly property bool done: !root.testing && (root.speed.down || 0) > 0
	readonly property real hero: root.testing ? (root.speed.live || 0) : (root.speed.down || 0)
	readonly property real ceiling: root.speed.ceiling || 1
	readonly property color testInk: root.speed.stage === "up" ? root.upInk : root.downInk
	readonly property string buttonText: root.testing
		? (root.speed.stage === "down" ? Config.networkSpeedTestingDown : Config.networkSpeedTestingUp)
		: root.done ? "\u{2193} " + root.speed.downText + " \u{2191} " + root.speed.upText + " " + Config.networkSpeedAgain
			: Config.networkSpeedNone

	title: Config.networkTitle
	detail: root.connection
	detailColor: root.downInk
	listInk: root.downInk
	totalInk: root.downInk
	showTotal: false
	showProcessList: false
	keyAction: function(event) {
		if (root.wifiTarget !== "") {
			if (Input.cancel(event)) {
				root.cancelWifi();
				event.accepted = true;
				return true;
			}

			return false;
		}

		if (root.dnsEditing) {
			if (Input.accept(event)) {
				root.confirmDns();
				event.accepted = true;
				return true;
			}

			return false;
		}

		if (root.dnsFocus)
			return Input.act(event, {
				up: () => root.leaveDns(),
				down: () => root.leaveDns(),
				accept: () => root.editDns(),
				space: () => root.editDns()
			});

		if (!root.testing && event.key === Qt.Key_Down && root.dns !== "") {
			root.enterDns();
			event.accepted = true;
			return true;
		}

		return Input.network(event, root);
	}
	panelWidth: Config.networkTooltipWidth
	panelPadding: Config.networkTooltipPadding

	function graphValues(dir) {
		return root.history.map(function (point) {
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

	function brailleMasks(values, peak, cells, dir) {
		const cols = cells * 2;
		const top = peak > 0 ? peak : 1;
		const quiet = 16 * 1024;
		const count = values.length;
		const masks = [];

		let i = count - cols;

		for (let c = 0; c < cells; c++) {
			let mask = 0;

			for (let k = 0; k < 2; k++) {
				const sample = i >= 0 && i < count ? values[i] : 0;

				i++;
				const value = Math.max(0, Number(sample) || 0);
				const lit = value < quiet ? 0 : Math.min(4, Math.floor(value / top * 4 + 0.5));

				if (lit > 0) {
					const dots = (1 << lit) - 1;
					mask |= dir === "up" ? dots << (k * 4) : dots << (4 - lit) << (k * 4);
				}
			}

			masks.push(mask);
		}

		return masks;
	}

	function graphDots(cells) {
		const out = [];
		const pitch = Config.networkGraphHeight / 8;
		const size = pitch * 0.76;
		const peak = root.scaleOf();

		pushDots(out, root.brailleMasks(graphValues("up"), peak, cells, "up"), 0, root.upInk, cells, pitch, size);
		pushDots(out, root.brailleMasks(graphValues("down"), peak, cells, "down"), 4, root.downInk, cells, pitch, size);

		return out;
	}

	function details() {
		const out = [];

		if (!root.net)
			return out;


		if (root.isWifi)
			out.push({ label: "signal", text: root.net.signalText, color: root.upInk });

		out.push({ label: "ipv4", text: root.link, color: Config.foreground });

		return out;
	}

	function scaleOf() {
		let top = 1;

		root.history.forEach(function (point) {
			top = Math.max(top, point.down, point.up);
		});

		return top;
	}

	function secured(security) {
		return security !== "" && security !== "--";
	}

	function openWifi(ssid, locked) {
		if (locked) {
			root.wifiTarget = ssid;
			root.wifiPassword = "";
			return;
		}

		Yudae.networkConnect(ssid, "");
	}

	function connectWifi() {
		if (root.wifiTarget === "")
			return;

		Yudae.networkConnect(root.wifiTarget, root.wifiPassword);
		root.cancelWifi();
	}

	function cancelWifi() {
		root.wifiTarget = "";
		root.wifiPassword = "";
		root.forceActiveFocus();
	}

	function primaryAction() {
		root.dnsFocus = false;

		if (root.testing)
			Yudae.networkSpeedCancel();
		else
			Yudae.networkSpeedTest();
	}

	function enterDns() {
		if (root.dns === "")
			return;

		root.dnsFocus = true;
		root.forceActiveFocus();
	}

	function leaveDns() {
		root.dnsFocus = false;
		root.selectRun();
	}

	function editDns() {
		if (root.dns === "")
			return;

		root.dnsFocus = true;
		root.dnsEditing = true;
		root.dnsCustom = root.dns;
	}

	function confirmDns() {
		const list = root.dnsCustom.trim();
		const conn = root.connection;

		if (!list || !conn)
			return;

		root.dnsEditing = false;
		Yudae.networkDns(conn, list);
		root.selectRun();
	}

	function selectRun() {
		if (runButton.visible)
			runButton.forceActiveFocus();
	}

	function unselectRun() {
		runButton.focus = false;
		root.forceActiveFocus();
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
				text: "\u{2193} " + root.net.downText
			}

			Text {
				id: rateUp

				anchors.left: rateDown.right
				anchors.leftMargin: Config.networkGraphGap * 3

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: root.upInk
				text: "\u{2191} " + root.net.upText
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

		Rectangle {
			width: parent.width
			height: 1
			color: Config.muted
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
			height: root.isWifi ? wifiColumn.implicitHeight : 0
			visible: height > 0

			Column {
				id: wifiColumn

				width: parent.width
				spacing: Config.networkRowGap

				Repeater {
					model: root.wifi

					delegate: Item {
						id: wifiRow

						required property var modelData

						readonly property bool current: wifiRow.modelData.inUse
						readonly property bool picked: root.wifiTarget === wifiRow.modelData.ssid
						readonly property bool locked: root.secured(wifiRow.modelData.security)
						readonly property bool hot: wifiRow.picked || wifiHit.containsMouse

						width: wifiColumn.width
						height: Config.networkRowHeight

						Highlight {
							active: wifiRow.picked || wifiHit.containsMouse
						}

						Text {
							id: wifiGlyph

							anchors.left: parent.left
							anchors.verticalCenter: parent.verticalCenter
							font.family: Config.fontFamily
							font.pixelSize: Settings.fontSize
							color: wifiRow.current ? root.downInk : (wifiRow.hot ? Config.launcherHighlightText : Config.muted)
							text: wifiRow.locked ? Config.networkLockIcon : Config.networkWifiIcons[Util.clamp(wifiRow.modelData.bars, 1, 4) - 1]
						}

						Text {
							id: wifiName

							anchors.left: wifiGlyph.right
							anchors.leftMargin: Config.networkGraphGap * 3
							anchors.right: wifiSignal.left
							anchors.rightMargin: Config.networkGraphGap * 3
							anchors.verticalCenter: parent.verticalCenter
							elide: Text.ElideRight
							font.family: Config.fontFamily
							font.pixelSize: Settings.fontSize
							color: wifiRow.hot ? Config.launcherHighlightText : Config.foreground
							text: wifiRow.modelData.ssid
						}

						Text {
							id: wifiSignal

							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							font.family: Config.fontFamily
							font.pixelSize: Settings.fontSize
							color: wifiRow.current ? root.downInk : Config.muted
							text: wifiRow.modelData.signalText
						}

						MouseArea {
							id: wifiHit

							anchors.fill: parent
							hoverEnabled: true

							onClicked: root.openWifi(wifiRow.modelData.ssid, wifiRow.locked)
						}
					}
				}

				Item {
					width: wifiColumn.width
					height: Config.networkRowHeight
					visible: root.wifiTarget !== ""

					Highlight {
						active: true
					}

					TextInput {
						anchors.fill: parent
						verticalAlignment: TextInput.AlignVCenter

						font.family: Config.fontFamily
						font.pixelSize: Settings.fontSize
						color: Config.launcherHighlightText
						echoMode: TextInput.Password
						selectByMouse: true
						focus: root.wifiTarget !== ""
						text: root.wifiPassword

						onTextEdited: root.wifiPassword = text
						onAccepted: root.connectWifi()
						onActiveFocusChanged: if (activeFocus) selectAll()

						Keys.onEscapePressed: (event) => {
							root.cancelWifi();
							event.accepted = true;
						}
					}

					Text {
						anchors.fill: parent
						verticalAlignment: Text.AlignVCenter
						visible: root.wifiPassword === ""
						font.family: Config.fontFamily
						font.pixelSize: Settings.fontSize
						color: Config.muted
						text: Config.networkPasswordHint
					}
				}
			}
		},

		Item {
			id: dnsRow

			visible: root.dns !== ""
			width: parent.width
			height: Math.max(dnsLabel.implicitHeight, dnsValue.implicitHeight)

			readonly property bool hot: !root.dnsEditing && (root.dnsFocus || dnsHit.containsMouse)
			readonly property bool live: root.dnsEditing

			Text {
				id: dnsLabel

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				text: "dns"
			}

			Highlight {
				active: dnsRow.hot
				fillParent: false
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				width: dnsValue.implicitWidth + 8
				height: dnsValue.implicitHeight + 4
			}

			Text {
				id: dnsValue

				visible: !dnsRow.live
				anchors.right: parent.right
				width: parent.width - dnsLabel.width - 8
				elide: Text.ElideRight
				horizontalAlignment: Text.AlignRight

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: dnsRow.hot ? Config.launcherHighlightText : Config.foreground
				text: root.dns
			}

			TextInput {
				visible: dnsRow.live
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				width: parent.width - dnsLabel.width - 8
				horizontalAlignment: Text.AlignRight

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				selectByMouse: true
				focus: dnsRow.live
				text: root.dnsCustom

				onTextEdited: root.dnsCustom = text
				onAccepted: root.confirmDns()
				onActiveFocusChanged: if (activeFocus) selectAll()

				Keys.onEscapePressed: (event) => {
					root.dnsEditing = false;
					root.forceActiveFocus();
					event.accepted = true;
				}
			}

			MouseArea {
				id: dnsHit
				anchors.fill: parent
				hoverEnabled: true
				visible: !dnsRow.live

				onClicked: root.editDns()
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
				valueText: root.speed.text || "0"
				arrow: root.speed.stage === "down" ? "\u{2193}" : root.speed.stage === "up" ? "\u{2191}" : ""
				arrowSide: root.speed.stage === "up" ? "left" : "right"
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

	Connections {
		target: root

		function onOnScreenChanged() {
			if (root.onScreen && root.isWifi)
				Yudae.networkScan();
		}
	}

	Connections {
		target: root.source

		function onTestPendingChanged() {
			if (root.source && root.source.testPending) {
				root.source.clearSpeedTest();
				Yudae.networkSpeedTest();
			}
		}
	}
}
