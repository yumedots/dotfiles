import QtQuick
import qs
import qs.ui
import qs.services

GlyphRow {
	id: row

	required property var modelData

	property string pendingSsid: ""
	property string targetSsid: ""

	readonly property bool pending: row.pendingSsid === row.modelData.ssid

	hoverable: true
	selected: row.targetSsid === row.modelData.ssid
	current: row.modelData.inUse === true
	glyph: Config.wifiGlyph(row.modelData.bars)
	label: row.modelData.ssid

	Text {
		visible: row.pending
		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		color: row.ink
		text: Config.networkWifiConnecting
	}

	Glyph {
		visible: !row.pending && row.modelData.locked === true
		size: Settings.fontSize
		color: row.ink
		glyph: Config.iconLock
	}
}
