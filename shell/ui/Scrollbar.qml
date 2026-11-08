import QtQuick
import qs

Rectangle {
	id: root

	property var view: null
	property Item edge: root.parent
	property int thickness: Config.scrollbarWidth

	width: root.thickness
	height: Math.max(12, root.view.height * root.view.height / Math.max(1, root.view.contentHeight))
	x: {
		root.parent.width;
		root.parent.x;
		return root.parent.mapFromItem(root.edge, root.edge.width - root.width, 0).x;
	}
	y: root.view.y + root.view.contentY / Math.max(1, root.view.contentHeight - root.view.height) * (root.view.height - height)
	color: Config.dim
	visible: root.view.contentHeight > root.view.height + 1
}
