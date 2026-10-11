import QtQuick
import Quickshell
import qs.ui
import qs

ProcessPanel {
	id: root

	property var battery: null
	property var governors: []
	property string governor: ""
	readonly property color accentInk: Util.pick(Config.mono, Config.powerBase, Config.powerBaseMono)
	readonly property color warnInk: Util.pick(Config.mono, Config.powerWarn, Config.powerWarnMono)
	readonly property color dangerInk: Util.pick(Config.mono, Config.powerDanger, Config.powerDangerMono)

	title: Config.powerTitle
	detail: root.battery ? Math.round(root.battery.pct) + "%" + (root.battery.charging ? " charging" : "") : Config.powerNoBattery
	detailColor: root.dangerColorFor(root.battery ? root.battery.pct : 100)
	listInk: root.accentInk
	totalInk: root.dangerColorFor(root.battery ? root.battery.pct : 100)
	panelWidth: Config.powerTooltipWidth
	panelPadding: Config.powerTooltipPadding
	topCount: Config.powerTopCount
	psField: "pcpu"
	rowText: (value) => value.toFixed(1) + "%"
	rowColor: (value) => root.dangerColorFor(0)

	function dangerColorFor(load) {
		return Color.dangerColor(root.accentInk, root.warnInk, root.dangerInk, Config.powerWarnAt, Config.powerDangerAt, load);
	}

	viz: Column {
		width: parent.width
		spacing: 6

		Repeater {
			model: root.governors

			delegate: Line {
				required property var modelData

				label: String(modelData)
				hint: String(modelData) === root.governor ? "on" : ""
				lit: false
				onPick: function () {
					root.governorPicked(String(modelData));
				}
			}
		}
	}

	signal governorPicked(string governor)

	component Line: Item {
		id: line

		property string label: ""
		property string hint: ""
		property bool lit: false
		property var onPick

		width: Config.powerTooltipWidth
		height: Config.displayRowHeight

		Highlight {
			id: hl

			active: line.lit || hit.containsMouse
		}

		Text {
			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: hl.ink
			text: line.label
		}

		Text {
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: hl.ink
			text: line.hint
		}

		MouseArea {
			id: hit

			anchors.fill: parent
			anchors.margins: -Config.barHitPadding
			hoverEnabled: true

			onClicked: if (line.onPick) line.onPick();
		}
	}
}
