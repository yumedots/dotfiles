import QtQuick
import qs

Text {
	id: root

	property string name: ""
	property string glyph: ""
	property color ink: Config.foreground
	property int pixelSize: Config.iconSize

	font.family: Config.fontFamily
	font.pixelSize: root.pixelSize
	color: root.ink
	text: root.glyph !== "" ? root.glyph : Config.glyph(root.name)
}
