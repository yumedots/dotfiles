import QtQuick
import qs.ui
import qs
import qs.services
import "../../tooltips"

BarStat {
	id: root

	inkId: "cpu"

	readonly property var source: Yudae.system.cpu || ({})
	readonly property var cores: root.source.cores || []

	pct: root.source.pct || 0
	barColor: Color.mixColor(Config.cpuBase, Config.red, root.pct / 100)
	icon: Config.iconCpu
	value: Math.round(root.pct) + "%"

	popupContent: Component {
		CpuMonitor {
			id: monitor

			source: root
			onCloseRequested: root.closePopup()
		}
	}
}
