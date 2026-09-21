import QtQuick
import Quickshell.Widgets

IconImage {
	id: root

	readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1

	backer.sourceSize.width: root.actualSize * root.dpr
	backer.sourceSize.height: root.actualSize * root.dpr
}
