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

		implicitHeight: Math.ceil(right.implicitHeight) + Theme.barTopPadding
		exclusiveZone: implicitHeight
		color: Theme.background

		SystemClock {
			id: clock
			precision: SystemClock.Seconds
		}

		Workspaces {
			anchors.left: parent.left
			anchors.bottom: parent.bottom
			anchors.bottomMargin: cpuStat.textOffset
		}

		BarText {
			anchors.horizontalCenter: parent.horizontalCenter
			anchors.bottom: parent.bottom
			anchors.bottomMargin: cpuStat.textOffset

			text: Qt.formatDateTime(clock.date, "HH:mm")
		}

		Row {
			id: right

			anchors.right: parent.right
			anchors.rightMargin: Theme.sidePadding
			anchors.bottom: parent.bottom
			spacing: Theme.spacing

			Tray {
				anchors.bottom: parent.bottom
				anchors.bottomMargin: Math.ceil(Theme.barThickness)
			}

			CpuStat {
				id: cpuStat
				anchors.bottom: parent.bottom
			}

			MemoryStat {
				anchors.bottom: parent.bottom
			}

			VolumeStat {
				anchors.bottom: parent.bottom
			}

			BarText {
				anchors.bottom: parent.bottom
				anchors.bottomMargin: cpuStat.textOffset

				text: Qt.formatDateTime(clock.date, "yyyy-MM-dd")
			}
		}
	}
}
