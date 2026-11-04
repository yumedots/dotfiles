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

	title: Config.powerGovernorTitle
	showTotal: true
	totalOverride: govStep.hoverLabel !== "" ? govStep.hoverLabel : root.governor
	totalInk: root.accentInk
	showProcessList: false
	showVms: false
	listInk: root.accentInk
	panelWidth: Config.powerTooltipWidth
	panelPadding: Config.powerTooltipPadding

	keyAction: function (event) {
		if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
			return false;

		root.awakePicked(!(root.awake && root.awake.manual === true));
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

			readonly property var state: root.awake || ({})
			readonly property bool held: state.held === true
			readonly property bool manual: state.manual === true
			readonly property bool agents: state.agents === true
			readonly property bool wanted: manual || agents
			readonly property string label: manual ? Config.powerAwakeOn : (agents ? Config.powerAwakeAuto : Config.powerAwakeOff)

			width: parent.width
			height: Math.max(awakeTitle.implicitHeight, awakeState.implicitHeight) + 8

			function toggle() {
				root.awakePicked(!awakeRow.manual);
			}

			Text {
				id: awakeGlyph

				anchors.left: parent.left
				anchors.verticalCenter: parent.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize + 2
				color: awakeHit.containsMouse ? Config.launcherHighlightText : (awakeRow.wanted ? root.accentInk : Config.dim)
				text: Config.powerAwakeGlyph
			}

			Text {
				id: awakeTitle

				anchors.left: awakeGlyph.right
				anchors.leftMargin: 6
				anchors.verticalCenter: parent.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: awakeHit.containsMouse ? Config.launcherHighlightText : (awakeRow.wanted ? Config.foreground : Config.dim)
				text: Config.powerAwakeTitle
			}

			Text {
				id: awakeState

				anchors.right: awakeCell.left
				anchors.rightMargin: 8
				anchors.verticalCenter: parent.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: awakeHit.containsMouse ? Config.launcherHighlightText : (awakeRow.wanted ? root.accentInk : Config.dim)
				text: awakeRow.label
			}

			Rectangle {
				id: awakeCell

				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter

				width: 8
				height: 8
				color: awakeRow.held ? root.accentInk : "transparent"
				border.width: 1
				border.color: awakeRow.wanted ? root.accentInk : Config.dim
			}

			MouseArea {
				id: awakeHit

				anchors.fill: parent
				hoverEnabled: true

				onClicked: awakeRow.toggle()
			}

			Highlight {
				anchors.fill: parent
				active: awakeHit.containsMouse
				z: -1
			}
		}
	]

	signal governorPicked(string governor)
	signal awakePicked(bool on)
}
