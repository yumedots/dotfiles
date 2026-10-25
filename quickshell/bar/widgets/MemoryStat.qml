import QtQuick
import qs.ui
import qs
import qs.services
import "../../tooltips"

BarStat {
	id: root

	inkId: "memory"

	readonly property var memory: Yudae.system.memory || null
	readonly property real usedGB: root.memory ? root.memory.used / 1024 / 1024 : 0

	pct: root.memory ? root.memory.pct : 0
	barColor: Ink.dangerColor(Config.memoryBase, Config.memoryWarn, Config.memoryDanger, Config.memoryWarnAt, Config.memoryDangerAt, root.pct)
	icon: Config.iconMemory
	value: root.usedGB.toFixed(1) + "G"

	popupContent: Component {
		MemoryMonitor {
			id: monitor

			source: root
			onCloseRequested: root.closePopup()
		}
	}
}
