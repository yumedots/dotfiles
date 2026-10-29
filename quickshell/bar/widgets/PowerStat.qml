import QtQuick
import qs.ui
import qs
import qs.services
import "../../tooltips"

BarStat {
	id: root

	readonly property var battery: (Yudae.system.battery && Yudae.system.battery.present) ? Yudae.system.battery : null
	readonly property var governors: Yudae.system.governors || []
	property string governor: Yudae.system.governor || ""
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
	iconLift: 2
	icon: root.batteryIcon(root.battery)
	barColor: root.battery === null ? Config.foreground : (root.battery.color || Config.powerBase)
	textColor: root.barColor
	pct: root.battery ? root.battery.pct : 0
	value: root.battery ? Math.round(root.battery.pct) + "%" : ""
	showBar: root.battery !== null

	function batteryIcon(battery) {
		if (!battery)
			return root.icons.plug;

		if (battery.charging)
			return root.icons.charge;

		if (battery.pct >= 95)
			return root.icons.full;

		if (battery.pct >= 60)
			return root.icons.high;

		if (battery.pct >= 30)
			return root.icons.mid;

		if (battery.pct >= 10)
			return root.icons.low;

		return root.icons.alert;
	}

	function setGovernor(next) {
		Yudae.systemCommand({ governor: next });
		root.governor = next;
	}

	popupContent: Component {
		PowerMonitor {
			id: monitor

			source: root
			onCloseRequested: root.closePopup()
			onGovernorPicked: function (next) {
				root.setGovernor(next);
			}
		}
	}
}
