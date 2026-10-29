import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.ui
import qs.services

ProcessPanel {
	id: root

	property bool dnsOpen: false
	property bool dnsTyping: false
	property string dnsDraft: ""
	property string wifiTarget: ""
	property string wifiPassword: ""

	readonly property var net: Yudae.network
	readonly property var speed: root.net.speed || ({})
	readonly property var wifi: root.net.wifi || []
	readonly property string connection: root.net.ssid || root.net.iface || ""
	readonly property string dns: root.net.dns || ""
	readonly property bool linked: root.net.connected === true
	readonly property bool isWifi: root.net.kind === "wifi"
	readonly property color downInk: Config.mono ? Config.networkDownMono : Config.networkDown
	readonly property color upInk: Config.mono ? Config.networkUpMono : Config.networkUp
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

		if (root.dnsTyping) {
			if (Input.accept(event)) {
				root.sendDns();
				event.accepted = true;
				return true;
			}

			return false;
		}

		const openDns = function() {
			root.dnsOpen = true;
			root.dnsTyping = true;
			root.dnsDraft = root.dns;
			Yudae.cmd("network", { dns: { action: "show", server: "" } });
		};

		const closeDns = function() {
			root.dnsOpen = false;
			root.selectRun();
		};

		if (root.dnsOpen)
			return Input.act(event, { up: closeDns, down: closeDns, accept: openDns, space: openDns });

		if (!root.testing && event.key === Qt.Key_Down && root.dns !== "") {
			root.dnsOpen = true;
			event.accepted = true;
			return true;
		}

		return Input.network(event, root);
	}
	panelWidth: Config.networkTooltipWidth
	panelPadding: Config.networkTooltipPadding

	function openWifi(ssid, locked) {
		if (locked) {
			root.wifiTarget = ssid;
			root.wifiPassword = "";
			return;
		}

		Yudae.cmd("network", { connect: { ssid: ssid, password: "" } });
	}

	function connectWifi() {
		if (root.wifiTarget === "")
			return;

		Yudae.cmd("network", { connect: { ssid: root.wifiTarget, password: root.wifiPassword || "" } });
		root.cancelWifi();
	}

	function cancelWifi() {
		root.wifiTarget = "";
		root.wifiPassword = "";
		root.forceActiveFocus();
	}

	function primaryAction() {
		root.dnsOpen = false;

		if (root.testing)
			Yudae.cmd("network", { speedCancel: true });
		else
			Yudae.cmd("network", { speed: true });
	}

	function sendDns() {
		const draft = root.dnsDraft.trim();

		root.dnsTyping = false;
		Yudae.cmd("network", { dns: { action: draft === "" ? "reset" : "set", server: draft } });
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
			width: parent.width
			height: Config.networkGraphHeight
			clip: true

			DotGraph {
				width: parent.width
				height: Config.networkGraphHeight / 2
				levels: root.net.graph ? root.net.graph.up : []
				ink: root.upInk
			}

			DotGraph {
				y: Config.networkGraphHeight / 2
				width: parent.width
				height: Config.networkGraphHeight / 2
				flip: true
				levels: root.net.graph ? root.net.graph.down : []
				ink: root.downInk
			}
		},

		Rectangle {
			width: parent.width
			height: 1
			color: Config.muted
		},

		Repeater {
			model: root.net.details || []

			delegate: Item {
				required property var modelData

				width: parent.width
				height: Math.max(detailLabel.implicitHeight, detailValue.implicitHeight)

				Text {
					id: detailLabel

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: modelData.ink === "up" ? root.upInk : Config.foreground
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
					color: modelData.ink === "up" ? root.upInk : Config.foreground
					text: modelData.text || Config.networkWiredNothing
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
						readonly property bool locked: wifiRow.modelData.locked === true
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
							text: wifiRow.locked ? Config.networkLockIcon : Config.networkWifiIcons[Calc.clamp(wifiRow.modelData.bars, 1, 4) - 1]
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

			visible: root.dns !== "" || root.net.dnsError !== ""
			width: parent.width
			height: Math.max(dnsLabel.implicitHeight, dnsValue.implicitHeight)

			readonly property bool hot: !dnsRow.live && (root.dnsOpen || dnsHit.containsMouse)
			readonly property bool live: root.dnsTyping || root.net.dnsPending === true

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
				text: root.net.dnsError || root.dns
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
				text: root.dnsDraft

				onTextEdited: root.dnsDraft = text
				onAccepted: root.sendDns()
				onActiveFocusChanged: if (activeFocus) selectAll()

				Keys.onEscapePressed: (event) => {
					root.dnsTyping = false;
					root.forceActiveFocus();
					event.accepted = true;
				}
			}

			MouseArea {
				id: dnsHit
				anchors.fill: parent
				hoverEnabled: true
				visible: !dnsRow.live

				onClicked: {
					root.dnsOpen = true;
					root.dnsTyping = true;
					root.dnsDraft = root.dns;
					Yudae.cmd("network", { dns: { action: "show", server: "" } });
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
				Yudae.cmd("network", { scan: true });
		}
	}

	Connections {
		target: root.source

		function onTestPendingChanged() {
			if (root.source && root.source.testPending) {
				root.source.clearSpeedTest();
				Yudae.cmd("network", { speed: true });
			}
		}
	}
}
