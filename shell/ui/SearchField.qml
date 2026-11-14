import QtQuick
import qs

Rectangle {
	id: root

	property alias text: input.text
	property string glyph: Config.launcherPrompt
	property string hintKey: ""
	property string hintText: ""
	property string placeholder: ""
	property int echoMode: TextInput.Normal
	property bool typing: false
	property color boxColor: Config.launcherSearchBox
	property real size: Config.launcherFontSize
	property real glyphSize: Math.round(root.size * 1.25)
	property real glyphSlot: 0
	property real gap: Math.round(root.size * 0.625)
	property real padding: Config.procSearchPadding
	property real boxHeight: 0
	property real corner: Config.rowRadius

	signal accepted()
	signal edited()
	signal keyPressed(var event)

	readonly property bool hint: !root.typing && root.hintKey !== "" && input.text === ""
	readonly property string hintLabel: root.hintText.length > root.hintKey.length ? root.hintText.slice(root.hintKey.length).trim() : ""
	readonly property real slot: root.slotWidth
	readonly property real slotWidth: root.glyphSlot > 0 ? root.glyphSlot : (root.glyph === "" ? 0 : root.glyphSize)
	readonly property real lineHeight: Math.round(root.size * 1.6)

	implicitWidth: 2 * root.padding + root.slot + root.gap + (root.hintKey !== "" ? keycap.implicitWidth : Config.procSearchMinWidth)
	implicitHeight: root.boxHeight > 0 ? root.boxHeight : root.lineHeight + 2 * root.padding
	color: root.boxColor
	radius: root.corner

	function focusInput() {
		input.forceActiveFocus();
	}

	function startTyping() {
		root.typing = true;
	}

	function clear() {
		input.text = "";
	}

	onTypingChanged: {
		if (root.typing)
			root.focusInput();
	}

	Glyph {
		id: icon

		anchors.left: parent.left
		anchors.leftMargin: root.padding
		anchors.verticalCenter: parent.verticalCenter

		width: root.slotWidth
		height: root.glyphSize
		size: root.glyphSize
		color: Config.foreground
		glyph: root.glyph
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
		text: root.hintKey + (root.hintLabel !== "" ? " " + root.hintLabel : "")
	}

	TextInput {
		id: input

		anchors.left: icon.right
		anchors.right: parent.right
		anchors.leftMargin: root.gap
		anchors.rightMargin: root.padding
		anchors.verticalCenter: parent.verticalCenter

		visible: !root.hint
		echoMode: root.echoMode
		clip: true
		focus: root.typing
		selectByMouse: false
		color: Config.foreground
		font.family: Config.fontFamily
		font.pixelSize: root.size
		selectionColor: Config.launcherHighlight
		selectedTextColor: Config.launcherHighlightText

		onAccepted: root.accepted()
		onTextEdited: root.edited()

		Keys.onPressed: function (event) {
			if (Input.cancel(event)) {
				root.typing = false;
				event.accepted = true;
				return;
			}

			root.keyPressed(event);
		}
	}

	Text {
		anchors.left: input.left
		anchors.verticalCenter: parent.verticalCenter

		visible: !root.hint && input.text === "" && root.placeholder !== ""
		font.family: Config.fontFamily
		font.pixelSize: root.size
		color: Config.muted
		text: root.placeholder
	}

	MouseArea {
		anchors.fill: parent

		onClicked: root.startTyping()
	}
}
