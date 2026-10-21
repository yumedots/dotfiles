import QtQuick
import qs
import qs.services
import qs.ui

// A dynamic bar icon.
//
// The bar draws its icons as font glyphs, and a glyph sits on the text baseline.
// A drawn icon has no baseline, so it needs a box that matches the glyphs: the
// same band of text, and centred in it.
//
// Every drawn icon in the bar goes through this, so they all end up in the same
// place.
Item {
	id: root

	// The icon, drawn into the slot.
	property Component component: null

	property color ink: Config.foreground

	// How far the icon is lifted off the line of text.
	property real lift: 0

	// The size of the icon. It is a square, centred in the line of text.
	property real drawnSize: 0

	// The metrics of the line of text the icon shares. These come from the
	// caller, so every icon in the bar measures against the same text.
	property real inkAbove: 0
	property real inkBelow: 0

	// The centre of the glyph ink the icon is drawn against. A drawn icon has
	// no baseline of its own, so it is centred on the glyphs beside it.
	property real inkCentre: 0

	Loader {
		id: slot

		active: root.component !== null
		sourceComponent: root.component

		// The icon is centred on the line of text, so it lines up with the
		// glyphs next to it.
		x: 0
		y: root.inkCentre - root.drawnSize / 2 - root.lift

		width: root.drawnSize
		height: root.drawnSize

		property color ink: root.ink
	}
}
