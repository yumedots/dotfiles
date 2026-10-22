import QtQuick
import QtQuick.Shapes
import qs

// A dynamic icon: a vector icon that can be redrawn every frame, unlike the
// font glyphs the bar normally uses.
//
// The icon is one filled path built from any number of closed subpaths. The
// odd-even fill rule means a subpath drawn inside another one punches a hole
// through it, which is how a face gets eyes.
//
// The caller supplies the geometry as flat [x, y, ...] arrays, so the same
// primitive can draw a static glyph, a morphing body, or a face with moving
// eyes.
Shape {
	id: root

	property color ink: Config.foreground

	// A list of closed subpaths, each a flat [x, y, ...] array in item
	// coordinates.
	property var subpaths: []

	preferredRendererType: Shape.CurveRenderer
	asynchronous: false

	// The subpaths are joined into one SVG path, so they stay separate
	// subpaths and a hole inside a subpath is punched out by the fill rule.
	readonly property string path: {
		let out = "";

		for (let i = 0; i < root.subpaths.length; i++) {
			const points = root.subpaths[i];

			if (!points || points.length < 6)
				continue;

			out += "M " + points[0].toFixed(2) + " " + points[1].toFixed(2);

			for (let p = 2; p < points.length; p += 2)
				out += " L " + points[p].toFixed(2) + " " + points[p + 1].toFixed(2);

			out += " Z ";
		}

		return out;
	}

	ShapePath {
		// The fill rule is left at its default, which is odd-even, so a subpath
		// drawn inside another one punches a hole through it.
		strokeColor: "transparent"
		fillColor: root.ink
		strokeWidth: 1

		PathSvg {
			path: root.path
		}
	}
}
