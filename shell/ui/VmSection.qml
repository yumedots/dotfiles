import QtQuick
import qs
import qs.services

Column {
	id: root

	readonly property var vms: Yudae.vms
	readonly property var budget: root.vms.budget || ({})
	readonly property var rows: root.vms.list || []
	readonly property int memUsed: root.budget.usedMemMb || 0
	readonly property int memMax: root.budget.memMb || 1
	readonly property int coresUsed: root.budget.usedCores || 0
	readonly property int coresMax: root.budget.cores || 1

	visible: root.rows.length > 0
	spacing: Config.procsGap

	Text {
		width: parent.width
		elide: Text.ElideRight

		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		color: Config.foreground
		text: "VMs " + (root.memUsed / 1024).toFixed(1) + "/" + Math.round(root.memMax / 1024) + " GB  " + root.coresUsed + "/" + root.coresMax + " cores"
	}

	Rectangle {
		width: parent.width
		height: 2
		color: Config.launcherSearchBox

		Rectangle {
			width: parent.width * Math.min(1, root.memUsed / root.memMax)
			height: parent.height
			color: Config.foreground
		}
	}

	Repeater {
		model: root.rows

		Item {
			required property var modelData

			width: root.width
			height: nameText.implicitHeight

			Text {
				id: nameText

				width: parent.width - usageText.width - 8
				elide: Text.ElideRight

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				text: modelData.name + "  " + modelData.tier + (modelData.gl ? "  gl" : "")
			}

			Text {
				id: usageText

				anchors.right: parent.right

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.muted
				text: Math.round(modelData.cpu) + "%  " + Math.round(modelData.rssKb / 1024) + "/" + modelData.memMb + " MB"
			}
		}
	}
}
