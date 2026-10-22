import QtQuick
import qs

// A braille spinner, for anything that is loading.
//
// The frames are the braille dots that turn, so the spinner is a text glyph
// and it sits with the rest of the type.
Item {
	id: root

	property bool running: true
	property color ink: Config.foreground
	property int size: Settings.fontSize

	// The frames are the braille dots that turn, so the spinner is a text
	// glyph and it sits with the rest of the type.
	readonly property var frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

	// The frame that is shown. It is turned by the timer below.
	property int frame: 0

	implicitWidth: glyph.implicitWidth
	implicitHeight: glyph.implicitHeight

	Timer {
		interval: 90
		repeat: true
		running: root.running

		onTriggered: root.frame = (root.frame + 1) % 10
	}

	Text {
		id: glyph

		anchors.centerIn: parent

		font.family: Config.fontFamily
		font.pixelSize: root.size
		color: root.ink
		text: root.frames[root.frame]
	}
}
