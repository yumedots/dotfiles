import QtQuick
import Quickshell
import "config.js" as Config

ShellRoot {
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

			implicitHeight: Math.ceil(right.implicitHeight) + Config.barTopPadding
			exclusiveZone: implicitHeight
			color: Config.background

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
				id: clockText

				anchors.horizontalCenter: parent.horizontalCenter
				anchors.bottom: parent.bottom
				anchors.bottomMargin: cpuStat.textOffset

				text: Qt.formatDateTime(clock.date, "HH:mm")
			}

			Row {
				id: right

				anchors.right: parent.right
				anchors.rightMargin: Config.sidePadding
				anchors.bottom: parent.bottom
				spacing: Config.spacing

				Tray {
					anchors.bottom: parent.bottom
					anchors.bottomMargin: Math.ceil(Config.barThickness)
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
					id: dateText

					anchors.bottom: parent.bottom
					anchors.bottomMargin: cpuStat.textOffset

					text: Qt.formatDateTime(clock.date, "yyyy-MM-dd")

					MouseArea {
						id: dateArea

						anchors.fill: parent
						hoverEnabled: true

						onClicked: calendarPopup.toggle()
						onExited: calendarPopup.scheduleClose()
					}
				}
			}

			Tooltip {
				id: calendarPopup

				anchorWindow: bar
				anchorItem: dateText
				anchorHovered: dateArea.containsMouse
				padding: 0

				Calendar {
					today: clock.date
				}
			}
		}
	}

	Dock {
		visible: Config.dockEnabled
	}
}
