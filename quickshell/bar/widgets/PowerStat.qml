import QtQuick
import Quickshell.Io
import qs.ui
import qs
import "../../tooltips"

BarStat {
	id: root

	property var battery: null
	property var governors: []
	property string governor: ""
	property bool applyFailed: false

	readonly property var icons: ({
		full: Config.iconBatteryFull,
		high: Config.iconBatteryHigh,
		mid: Config.iconBatteryMid,
		low: Config.iconBatteryLow,
		alert: Config.iconBatteryAlert,
		charge: Config.iconBatteryCharge,
		plug: Config.iconPowerPlug
	})

	dim: root.applyFailed
	dimColor: Config.muted
	icon: System.batteryIcon(root.battery, root.icons)
	barColor: root.battery === null ? Config.foreground : Color.dangerColor(Config.powerBase, Config.powerWarn, Config.powerDanger, Config.powerWarnAt, Config.powerDangerAt, root.battery.pct)
	textColor: root.barColor
	pct: root.battery ? root.battery.pct : 0
	value: root.battery ? Math.round(root.battery.pct) + "%" : ""
	showBar: root.battery !== null

	function refresh() {
		batteryFile.reload();
		governorFile.reload();
	}

	function setGovernor(next) {
		setGovernorProcess.command = System.governorCommand(next);
		setGovernorProcess.running = true;
	}

function handleGovernors(text) {
		root.governors = System.cpuGovernors(text);
		root.governor = System.currentGovernor(text);
	}

	FileView {
		id: batteryFile

		path: "/sys/class/power_supply/BAT0/uevent"
		blockLoading: true
		onLoaded: root.battery = System.parseBattery(batteryFile.text())
	}

	FileView {
		id: governorFile

		path: "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"
		blockLoading: true
		onLoaded: root.handleGovernors(governorFile.text())
	}

	Process {
		id: setGovernorProcess

		onExited: {
			if (exitCode !== 0) {
				root.applyFailed = true;
				failTimer.restart();
			}

			root.refresh();
		}
	}

	Timer {
		id: failTimer

		interval: 2000
		repeat: false
		onTriggered: root.applyFailed = false
	}

	Timer {
		interval: 5000
		running: true
		repeat: true
		triggeredOnStart: true
		onTriggered: root.refresh()
	}

	popupContent: Component {
		PowerMonitor {
			id: monitor

			source: root
			battery: root.battery
			governors: root.governors
			governor: root.governor
			onCloseRequested: root.closePopup()
			onGovernorPicked: function (next) {
				root.setGovernor(next);
				root.governor = next;
			}
		}
	}
}
