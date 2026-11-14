import QtQuick
import QtQuick.Shapes
import qs

// A dynamic icon: a vector icon that can be redrawn every frame, unlike the
// font glyphs the bar normally uses.
//
// The icon is one filled path built from a few closed subpaths. The odd-even
// fill rule means a subpath drawn inside another one punches a hole through
// it, which is how a face gets eyes.
//
// The caller supplies the geometry as flat [x, y, ...] arrays, so the same
// primitive can draw a static glyph, a morphing body, or a face with moving
// eyes.
Shape {
	id: root

	property color ink: Config.foreground

	// The subpaths, each a flat [x, y, ...] array in item coordinates.
	property var subpaths: []

	preferredRendererType: Shape.GeometryRenderer
	asynchronous: false

	ShapePath {
		// The fill rule is left at its default, which is odd-even, so a subpath
		// drawn inside another one punches a hole through it.
		strokeColor: "transparent"
		fillColor: root.ink
		strokeWidth: 1

		PathPolyline {
			path: root.points(0)
		}

		PathPolyline {
			path: root.points(1)
		}

		PathPolyline {
			path: root.points(2)
		}

		PathPolyline {
			path: root.points(3)
		}
	}

	property var sourced: [null, null, null, null]
	property var converted: [null, null, null, null]

	// The points of one subpath, as the list the path wants. A subpath that is
	// the same array as last time keeps the list that was built for it, so only
	// the subpaths that moved are converted again.
	function points(index) {
		const subpath = root.subpaths.length > index ? root.subpaths[index] : null;

		if (!subpath)
			return [];

		if (root.sourced[index] === subpath)
			return root.converted[index];

		const out = [];

		for (let i = 0; i < subpath.length; i += 2)
			out.push(Qt.point(subpath[i], subpath[i + 1]));

		root.sourced[index] = subpath;
		root.converted[index] = out;

		return out;
	}
}
