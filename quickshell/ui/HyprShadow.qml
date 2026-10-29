import QtQuick
import qs.services

Item {
	id: root

	property bool shadowEnabled: true
	readonly property var settings: Yudae.screenShadow
	readonly property bool active: root.shadowEnabled && root.settings.enabled && root.settings.range > 0
	readonly property color tint: Qt.color(root.qmlColor(root.settings.color))
	readonly property int steps: 24
	readonly property real reach: root.settings.range * 0.8
	readonly property real inset: Math.abs(root.settings.offsetY) * 0.55
	readonly property real falloff: 2.3
	property real topReach: -1
	property real bottomReach: -1
	readonly property real clipTop: root.topReach >= 0 ? root.topReach : root.reach + Math.abs(root.settings.offsetY)
	readonly property real clipBottom: root.bottomReach >= 0 ? root.bottomReach : root.reach + Math.abs(root.settings.offsetY)
	readonly property real clipSide: root.reach + Math.abs(root.settings.offsetX)

	function qmlColor(value) {
		const text = String(value || "");
		let match = text.match(/^rgba\(([0-9a-f]{8})\)$/i);

		if (match)
			return "#" + match[1].slice(6, 8) + match[1].slice(0, 6);

		match = text.match(/^rgb\(([0-9a-f]{6})\)$/i);

		if (match)
			return "#" + match[1];

		match = text.match(/^0x([0-9a-f]{8})$/i);

		return match ? "#" + match[1] : text || "#70000000";
	}

	Item {
		x: -root.clipSide
		y: -root.clipTop
		width: root.width + 2 * root.clipSide
		height: root.height + root.clipTop + root.clipBottom
		clip: true

		Repeater {
			model: root.active ? root.steps : 0

			delegate: Rectangle {
				required property int index

				readonly property real grow: root.reach * (index + 1) / root.steps
				readonly property real before: root.tint.a * 0.95 * Math.pow(1 - index / root.steps, root.falloff)
				readonly property real after: root.tint.a * 0.95 * Math.pow(1 - (index + 1) / root.steps, root.falloff)

				x: root.clipSide + root.settings.offsetX - grow + root.inset
				y: root.clipTop + root.settings.offsetY - grow + root.inset
				width: root.width + 2 * (grow - root.inset)
				height: root.height + 2 * (grow - root.inset)
				radius: grow
				color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 1 - (1 - before) / (1 - after))
			}
		}
	}
}
