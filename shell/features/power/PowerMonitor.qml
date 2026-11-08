import QtQuick
import qs.ui
import qs

ProcessPanel {
	id: root

	property var governors: root.source ? root.source.governors : []
	property string governor: root.source ? root.source.governor : ""
	property var battery: root.source ? root.source.battery : null
	property var awake: root.source ? root.source.awake : null

	readonly property color accentInk: Config.mono ? Config.powerBaseMono : Config.powerBase
	readonly property int governorIndex: Math.max(0, root.governors.indexOf(root.governor))
	readonly property var awakeModes: [
		{ value: "off", label: Config.iconAwakeOff },
		{ value: "auto", label: Config.iconAwakeAuto },
		{ value: "on", label: Config.iconAwakeOn }
	]
	readonly property string awakeMode: root.awake && root.awake.mode ? root.awake.mode : "auto"
	readonly property int awakeIndex: Math.max(0, root.awakeModes.findIndex((entry) => entry.value === root.awakeMode))

	function cycleAwake() {
		const next = root.awakeModes[(root.awakeIndex + 1) % root.awakeModes.length];

		root.awakePicked(next.value);
	}

	title: Config.powerGovernorTitle
	showTotal: true
	totalOverride: govStep.hoverLabel !== "" ? govStep.hoverLabel : root.governor
	totalInk: root.accentInk
	showProcessList: false
	listInk: root.accentInk
	panelWidth: Config.powerTooltipWidth
	panelPadding: Config.powerTooltipPadding

	keyAction: function (event) {
		if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
			return false;

		root.cycleAwake();
		event.accepted = true;
		return true;
	}

	viz: [
		PowerFlow {
			visible: root.battery !== null
			width: parent.width
			height: Config.powerFlowHeight
			flow: root.source ? root.source.flow : 0
			watts: root.battery ? root.battery.watts || 0 : 0
			fill: root.battery ? root.battery.pct / 100 : 1
			hotInk: !Config.mono && root.battery && root.battery.color ? root.battery.color : root.accentInk
		},

		StepBar {
			id: govStep

			width: parent.width
			model: root.governors
			selected: root.governorIndex
			ink: root.accentInk
			onPick: (next) => root.governorPicked(String(next))
		},

		Rectangle {
			width: parent.width
			height: 1
			color: Config.dim
		},

		Item {
			id: awakeRow

			readonly property bool armed: root.awakeMode !== "off"

			width: parent.width
			height: Math.max(awakeTitle.implicitHeight, awakeSwitch.implicitHeight) + 8

			Text {
				id: awakeGlyph

				anchors.left: parent.left
				anchors.verticalCenter: parent.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize + 2
				color: awakeRow.armed ? root.accentInk : Config.dim
				text: Config.iconAwake
			}

			Text {
				id: awakeTitle

				anchors.left: awakeGlyph.right
				anchors.leftMargin: 6
				anchors.verticalCenter: parent.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: awakeRow.armed ? Config.foreground : Config.dim
				text: Config.powerAwakeTitle
			}

			PillSwitch {
				id: awakeSwitch

				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter

				model: root.awakeModes
				selected: root.awakeIndex
				ink: root.accentInk

				onPick: (value) => root.awakePicked(String(value))
			}
		}
	]

	signal governorPicked(string governor)
	signal awakePicked(string mode)
}
