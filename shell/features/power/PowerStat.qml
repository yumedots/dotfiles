import QtQuick
import qs.ui
import qs
import qs.services

BarStat {
	id: root

	readonly property var demo: ({ present: true, pct: 72, charging: false, state: "Discharging", watts: 14.5, color: Config.powerBase })
	readonly property var battery: (Yudae.system.battery && Yudae.system.battery.present) ? Yudae.system.battery : (Config.powerDemo ? root.demo : null)
	readonly property var governors: Yudae.system.governors || []
	property string governor: Yudae.system.governor || ""
	readonly property var awake: Yudae.system.awake || null
	property bool applyFailed: false
	readonly property int flow: !root.battery ? 0 : (root.battery.state === "Charging" ? 1 : (root.battery.state === "Discharging" ? -1 : 0))

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
	iconLift: root.battery === null ? 2 : 0
	icon: root.batteryIcon(root.battery)
	barColor: root.battery === null ? Config.foreground : (root.battery.color || Config.powerBase)
	textColor: root.barColor
	pct: root.battery ? root.battery.pct : 0
	value: root.battery ? Math.round(root.battery.pct) + "%" : ""
	showBar: root.battery !== null
	iconWidth: 20
	iconHeight: root.iconInkHeight
	iconComponent: root.battery === null ? null : flowIcon

	Component {
		id: flowIcon

		PowerFlow {
			width: parent.width
			height: parent.height
			rows: 4
			span: 2
			frequency: 1.4
			amplitude: 0.35
			dotScale: 0.95
			sparse: true
			paused: !root.onScreen
			flow: root.flow
			watts: root.battery ? root.battery.watts || 0 : 0
			fill: root.battery ? root.battery.pct / 100 : 1
			hotInk: parent.ink
		}
	}

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

	function setKeepAwake(mode) {
		Yudae.systemCommand({ keepAwake: mode });
	}

	popupContent: Component {
		PowerMonitor {
			id: monitor

			source: root
			onCloseRequested: root.closePopup()
			onGovernorPicked: function (next) {
				root.setGovernor(next);
			}
			onAwakePicked: function (mode) {
				root.setKeepAwake(mode);
			}
		}
	}
}
