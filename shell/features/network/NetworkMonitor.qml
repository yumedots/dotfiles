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
	property bool listOpen: false
	property bool othersOpen: false

	readonly property var net: Yudae.network
	readonly property var speed: root.net.speed || ({})
	readonly property var wifi: root.net.wifi || []
	readonly property string dns: root.net.dns || ""
	readonly property bool linked: root.net.connected === true
	readonly property bool isWifi: root.net.kind === "wifi"
	readonly property bool radio: root.net.radio !== false
	readonly property bool hasWifi: root.net.hasWifi === true
	readonly property bool showList: root.hasWifi && root.radio
	readonly property var adapters: root.net.adapters || []
	readonly property var knownWifi: root.wifi.filter((entry) => entry.saved === true || entry.inUse === true)
	readonly property var otherWifi: root.wifi.filter((entry) => entry.saved !== true && entry.inUse !== true)
	readonly property int litBars: {
		for (let i = 0; i < root.wifi.length; i++) {
			if (root.wifi[i].inUse === true)
				return Calc.clamp(root.wifi[i].bars, 1, 4);
		}

		return 0;
	}
	readonly property string wifiError: root.net.wifiError || ""
	readonly property string wifiAsk: root.net.wifiAsk || ""
	readonly property var radioModes: [
		{ value: false, label: Config.iconWifiOff },
		{ value: true, label: Config.iconWifi4 }
	]
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

	function adapterOf(kind) {
		for (let i = 0; i < root.adapters.length; i++) {
			if (root.adapters[i].kind === kind)
				return root.adapters[i];
		}

		return null;
	}

	function useKind(kind) {
		Yudae.cmd("network", { use: { kind: kind } });
	}

	function openWifi(entry) {
		if (entry.locked && !entry.saved) {
			root.wifiTarget = entry.ssid;
			return;
		}

		Yudae.cmd("network", { connect: { ssid: entry.ssid, password: "" } });
	}

	onWifiAskChanged: {
		if (root.wifiAsk === "")
			return;

		root.wifiTarget = root.wifiAsk;
		root.listOpen = true;
		root.othersOpen = true;
	}

	function sendPassword(password) {
		if (root.wifiTarget === "")
			return;

		Yudae.cmd("network", { connect: { ssid: root.wifiTarget, password: password } });
		root.cancelWifi();
	}

	function cancelWifi() {
		root.wifiTarget = "";
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
		Column {
			id: adapterBlock

			width: parent.width
			height: root.hasWifi ? implicitHeight : 0
			visible: root.hasWifi
			spacing: Config.networkRowGap

			Column {
				id: adapterColumn

				width: parent.width
				spacing: Config.networkRowGap

				GlyphRow {
					id: lanRow

					readonly property var adapter: root.adapterOf("ethernet")

					width: parent.width
					visible: lanRow.adapter !== null
					height: visible ? implicitHeight : 0
					hoverable: true
					glyph: Config.iconEthernet
					label: lanRow.adapter && lanRow.adapter.connected ? (lanRow.adapter.connection || Config.networkEthernetLabel) : Config.networkEthernetLabel
					current: lanRow.adapter !== null && lanRow.adapter.active
					dim: lanRow.adapter !== null && !lanRow.adapter.connected

					onActivated: root.useKind("ethernet")
				}

				GlyphRow {
					id: radioRow

					readonly property var adapter: root.adapterOf("wifi")

					width: parent.width
					hoverable: true
					glyph: !root.radio ? Config.iconWifiOff
						: Config.wifiGlyph(root.litBars > 0 ? root.litBars : 4)
					label: !root.radio ? Config.networkWifiOff
						: radioRow.adapter && radioRow.adapter.connected ? (radioRow.adapter.connection || Config.networkWifiLabel)
						: Config.networkWifiIdle
					current: radioRow.adapter !== null && radioRow.adapter.active
					dim: !root.radio || radioRow.adapter === null || !radioRow.adapter.connected

					onActivated: {
						if (root.radio)
							root.listOpen = !root.listOpen;

						if (radioRow.adapter && radioRow.adapter.connected && !radioRow.adapter.active)
							root.useKind("wifi");
					}

					Item {
						width: Config.toggleHeight
						height: Config.toggleHeight
						visible: root.radio

						Rectangle {
							anchors.fill: parent
							radius: width / 2
							color: Config.toggleHover
							visible: chevronHit.containsMouse
						}

						Glyph {
							anchors.fill: parent
							size: Settings.fontSize
							color: Config.foreground
							glyph: root.listOpen ? Config.iconUp : Config.iconDown
						}

						MouseArea {
							id: chevronHit

							anchors.fill: parent
							hoverEnabled: true

							onClicked: root.listOpen = !root.listOpen
						}
					}

					PillSwitch {
						model: root.radioModes
						selected: root.radio ? 1 : 0
						ink: root.downInk

						onPick: (value) => Yudae.cmd("network", { radio: { on: value === true } })
					}
				}
			}

			Drawer {
				id: wifiDrawer

				width: parent.width
				maxHeight: Config.networkDropdownRows * (Config.rowHeight + Config.networkRowGap) + 2 * Config.rowInset
				open: root.showList && root.listOpen

				Repeater {
					model: root.knownWifi

					delegate: NetworkEntry {
						width: parent.width
						pendingSsid: root.net.wifiPending || ""
						targetSsid: root.wifiTarget
						errorText: root.wifiError
						errorInk: root.upInk

						onActivated: root.openWifi(modelData)
						onSubmitted: (password) => root.sendPassword(password)
						onCancelled: root.cancelWifi()
					}
				}

				GlyphRow {
					width: parent.width
					visible: root.otherWifi.length > 0 && root.knownWifi.length > 0
					height: visible ? implicitHeight : 0
					hoverable: true
					glyph: root.othersOpen ? Config.iconUp : Config.iconDown
					label: Config.networkOtherLabel

					onActivated: root.othersOpen = !root.othersOpen
				}

				Repeater {
					model: root.othersOpen || root.knownWifi.length === 0 ? root.otherWifi : []

					delegate: NetworkEntry {
						width: parent.width
						pendingSsid: root.net.wifiPending || ""
						targetSsid: root.wifiTarget
						errorText: root.wifiError
						errorInk: root.upInk

						onActivated: root.openWifi(modelData)
						onSubmitted: (password) => root.sendPassword(password)
						onCancelled: root.cancelWifi()
					}
				}
			}
		},

		Separator {
			width: parent.width
			visible: root.hasWifi
			height: root.hasWifi ? implicitHeight : 0
		},

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

		Separator {
			width: parent.width
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
				radius: height / 2
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

				radius: height / 2
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
			if (root.onScreen)
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
