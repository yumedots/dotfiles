import QtQuick
import qs

Item {
	id: root

	property var model: []
	property int selected: 0
	property color ink: Config.foreground
	property color track: Config.toggleTrack
	property color hoverInk: Config.toggleHover
	property color labelInk: Config.toggleLabelInk
	property color fadedInk: Config.toggleFaded
	property var onPick

	readonly property int count: root.model.length
	readonly property int ready: slots.count
	readonly property real knobSize: Math.max(0, root.height - Config.togglePadding * 2)
	readonly property var active: root.selected >= 0 && root.selected < root.count && root.ready > root.selected ? slots.itemAt(root.selected) : null

	implicitHeight: Config.toggleHeight
	implicitWidth: row.implicitWidth + Config.togglePadding * 2

	function labelOf(entry) {
		if (entry === null || entry === undefined)
			return Config.toggleEmpty;

		if (typeof entry === "object")
			return entry.label !== undefined ? String(entry.label) : Config.toggleEmpty;

		return String(entry);
	}

	function valueOf(entry) {
		return entry !== null && entry !== undefined && entry.value !== undefined ? entry.value : entry;
	}

	function pick(entry) {
		if (root.onPick)
			root.onPick(root.valueOf(entry));
	}

	Rectangle {
		anchors.fill: parent
		radius: height / 2
		color: root.track
	}

	Rectangle {
		id: knob

		x: root.active ? Config.togglePadding + root.active.x + (root.active.width - width) / 2 : Config.togglePadding
		y: Config.togglePadding
		width: Math.max(root.knobSize, root.active ? root.active.labelWidth + Config.toggleLabelPad * 2 : 0)
		height: root.knobSize
		radius: height / 2
		color: root.ink

		Behavior on x {
			NumberAnimation {
				duration: Config.toggleMs
				easing.type: Easing.OutCubic
			}
		}

		Behavior on width {
			NumberAnimation {
				duration: Config.toggleMs
				easing.type: Easing.OutCubic
			}
		}
	}

	Row {
		id: row

		x: Config.togglePadding
		height: parent.height

		Repeater {
			id: slots

			model: root.model

			delegate: Item {
				id: slot

				required property var modelData
				required property int index

				readonly property real labelWidth: label.inkWidth

				width: Math.max(root.knobSize, slot.labelWidth + Config.toggleLabelPad * 2)
				height: row.height

				Rectangle {
					anchors.centerIn: parent

					width: root.knobSize
					height: root.knobSize
					radius: width / 2
					color: root.hoverInk
					visible: hover.containsMouse && slot.index !== root.selected
				}

				Glyph {
					id: label

					anchors.fill: parent
					size: Config.toggleFontSize
					color: slot.index === root.selected ? root.labelInk : (hover.containsMouse ? root.ink : root.fadedInk)
					glyph: root.labelOf(slot.modelData)
				}

				MouseArea {
					id: hover

					anchors.fill: parent
					hoverEnabled: true

					onClicked: root.pick(slot.modelData)
				}
			}
		}
	}
}
