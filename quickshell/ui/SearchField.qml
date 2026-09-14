import QtQuick
import qs

Rectangle {
	id: root

	property alias text: input.text
	property string glyph: Config.launcherPrompt
	property string keyLabel: ""
	property string placeholder: Config.procSearchPlaceholder
	property bool active: false
	property color boxColor: Config.launcherSearchBox
	property real size: Config.launcherFontSize
	property real glyphSize: Math.round(root.size * 1.25)
	property real glyphSlot: 0
	property real gap: Math.round(root.size * 0.625)
	property real padding: Config.procSearchPadding
	property real boxHeight: 0

	signal accepted()
	signal canceled()
	signal edited()
	signal navigate(int step)
	signal keyPressed(var event)

	readonly property bool hint: !root.active && root.keyLabel !== ""
	readonly property real slot: root.glyphSlot > 0 ? root.glyphSlot : icon.implicitWidth
	readonly property real lineHeight: Math.round(root.size * 1.6)

	implicitWidth: 2 * root.padding + root.slot + root.gap + (root.keyLabel !== "" ? keycap.implicitWidth : Config.procSearchMinWidth)
	implicitHeight: root.boxHeight > 0 ? root.boxHeight : root.lineHeight + 2 * root.padding
	color: root.boxColor
	radius: 0

	function focusInput() {
		input.forceActiveFocus();
	}

	function clear() {
		input.text = "";
	}

	onActiveChanged: {
		if (root.active)
			root.focusInput();
	}

	Text {
		id: icon

		anchors.left: parent.left
		anchors.leftMargin: root.padding
		anchors.verticalCenter: parent.verticalCenter

		width: root.slot
		horizontalAlignment: Text.AlignHCenter

		font.family: Config.fontFamily
		font.pixelSize: root.glyphSize
		color: Config.foreground
		text: root.glyph
	}

	Text {
		id: keycap

		anchors.left: icon.right
		anchors.leftMargin: root.gap
		anchors.verticalCenter: parent.verticalCenter

		visible: root.hint
		font.family: Config.fontFamily
		font.pixelSize: root.size
		color: Config.muted
		text: root.keyLabel
	}

	TextInput {
		id: input

		anchors.left: icon.right
		anchors.right: parent.right
		anchors.leftMargin: root.gap
		anchors.rightMargin: root.padding
		anchors.verticalCenter: parent.verticalCenter

		visible: !root.hint
		clip: true
		focus: root.active
		selectByMouse: false
		color: Config.foreground
		font.family: Config.fontFamily
		font.pixelSize: root.size
		selectionColor: Config.launcherHighlight
		selectedTextColor: Config.launcherHighlightText

		onAccepted: root.accepted()
		onTextEdited: root.edited()

		Keys.onEscapePressed: function (event) {
			root.canceled();
			event.accepted = true;
		}

		Keys.onUpPressed: function (event) {
			root.navigate(-1);
			event.accepted = true;
		}

		Keys.onDownPressed: function (event) {
			root.navigate(1);
			event.accepted = true;
		}

		Keys.onPressed: function (event) {
			root.keyPressed(event);
		}
	}

	Text {
		id: placeholderText

		anchors.left: input.left
		anchors.verticalCenter: parent.verticalCenter

		visible: !root.hint && input.text === ""
		font.family: Config.fontFamily
		font.pixelSize: root.size
		color: Config.muted
		text: root.placeholder
	}
}
