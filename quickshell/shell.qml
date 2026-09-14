import QtQuick
import Quickshell
import Quickshell.Io
import "ui"
import "bar/widgets"
import "tooltips"
import "launcher"
import "dock"
import "config.js" as Config

ShellRoot {
	IpcHandler {
		target: "shell"

		function launcher() {
			launcherWindow.toggle();
		}

		function windows() {
			launcherWindow.toggleWindows();
		}
	}

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

			margins {
				top: border.gapsOut
				left: border.gapsOut
				right: border.gapsOut
			}

			readonly property real contentShift: (Math.ceil(right.implicitHeight) - clockText.implicitHeight) / 2

			implicitHeight: Math.ceil(right.implicitHeight) + 2 * border.inset
			exclusiveZone: implicitHeight
			color: "transparent"

			HyprBorder {
				id: border

				anchors.fill: parent
				padding: border.gapsIn
			}

			SystemClock {
				id: clock
				precision: SystemClock.Seconds
			}

			Workspaces {
				anchors.left: parent.left
				anchors.leftMargin: border.inset
				anchors.bottom: parent.bottom
				anchors.bottomMargin: cpuStat.textOffset + border.inset - bar.contentShift
			}

			BarText {
				id: clockText

				anchors.horizontalCenter: parent.horizontalCenter
				anchors.bottom: parent.bottom
				anchors.bottomMargin: cpuStat.textOffset + border.inset - bar.contentShift

				text: Qt.formatDateTime(clock.date, "HH:mm")
			}

			Row {
				id: right

				anchors.right: parent.right
				anchors.rightMargin: border.inset
				anchors.bottom: parent.bottom
				anchors.bottomMargin: border.inset - bar.contentShift
				spacing: Config.spacing

				Tray {
					anchors.bottom: parent.bottom
					anchors.bottomMargin: Math.ceil(Config.barThickness)
				}

				CpuStat {
					id: cpuStat
					anchors.bottom: parent.bottom

					onClicked: cpuPopup.toggle()
					onExited: cpuPopup.scheduleClose()
				}

				MemoryStat {
					id: memoryStat
					anchors.bottom: parent.bottom

					onClicked: memoryPopup.toggle()
					onExited: memoryPopup.scheduleClose()
				}

				VolumeStat {
					id: volumeStat

					anchors.bottom: parent.bottom

					onClicked: volumePopup.toggle()
					onExited: volumePopup.scheduleClose()
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
				id: cpuPopup

				anchorWindow: bar
				anchorItem: cpuStat
				anchorHovered: cpuStat.hovered

				CpuMonitor {
					source: cpuStat
				}
			}

			Tooltip {
				id: memoryPopup

				anchorWindow: bar
				anchorItem: memoryStat
				anchorHovered: memoryStat.hovered

				MemoryMonitor {
					source: memoryStat
				}
			}

			Tooltip {
				id: volumePopup

				anchorWindow: bar
				anchorItem: volumeStat
				anchorHovered: volumeStat.hovered

				VolumeMixer {}
			}

			Tooltip {
				id: calendarPopup

				anchorWindow: bar
				anchorItem: dateText
				anchorHovered: dateArea.containsMouse

				Calendar {
					today: clock.date
				}
			}
		}
	}

	Dock {
		visible: Config.dockEnabled
		onLauncherRequested: launcherWindow.toggle()
	}

	Launcher {
		id: launcherWindow
	}
}
