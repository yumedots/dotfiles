import QtQuick
import Quickshell
import "theme.js" as Theme

Variants {
	model: Quickshell.screens

	PanelWindow {
		id: bar

		required property var modelData
		screen: modelData

		anchors {
			top: true
			left: true
			right: true
		}

		implicitHeight: Theme.barHeight
		exclusiveZone: Theme.barHeight
		color: Theme.background

		SystemClock {
			id: clock
			precision: SystemClock.Seconds
		}

		Workspaces {
			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
		}

		Text {
			anchors.horizontalCenter: parent.horizontalCenter
			anchors.verticalCenter: parent.verticalCenter

			font.family: Theme.fontFamily
			font.pixelSize: Theme.fontSize
			color: Theme.foreground
			text: Qt.formatDateTime(clock.date, "HH:mm")
		}

		Row {
			id: right

			anchors.right: parent.right
			anchors.rightMargin: Theme.sidePadding
			anchors.verticalCenter: parent.verticalCenter
			spacing: Theme.spacing

			Tray {
				anchors.verticalCenter: parent.verticalCenter
			}

			CpuStat {
				anchors.bottom: parent.bottom
			}

			MemoryStat {
				anchors.bottom: parent.bottom
			}

			VolumeStat {
				anchors.bottom: parent.bottom
			}

			Text {
				anchors.verticalCenter: parent.verticalCenter

				font.family: Theme.fontFamily
				font.pixelSize: Theme.fontSize
				color: Theme.foreground
				text: Qt.formatDateTime(clock.date, "yyyy-MM-dd")
			}
		}
	}
}
