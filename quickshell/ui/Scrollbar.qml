import QtQuick
import qs

Rectangle {
	id: root

	property var view: null
	property real offset: 0
	property int thickness: Config.scrollbarWidth

	width: root.thickness
	height: Math.max(12, root.view.height * root.view.height / Math.max(1, root.view.contentHeight))
	x: root.view.x + root.view.width + root.offset
	y: root.view.contentY / Math.max(1, root.view.contentHeight - root.view.height) * (root.view.height - height)
	color: Config.muted
	visible: root.view.contentHeight > root.view.height + 1
}
