import QtQuick
import QtQuick.Shapes
import qs

Shape {
	id: root

	property int version: 1
	property real morph: 0
	property real exponent: root.shape.exponent
	property color color: Config.foreground

	preferredRendererType: Shape.CurveRenderer
	asynchronous: false

	readonly property var shape: Figure.figureShape(root.version)
	readonly property var outline: Figure.figurePoints({
		width: root.width,
		height: root.height,
		exponent: root.exponent,
		lobes: root.shape.lobes === undefined ? Config.figureLobes : root.shape.lobes,
		scallop: root.shape.scallop === undefined ? Config.figureScallop : root.shape.scallop,
		morph: root.morph
	})

	ShapePath {
		strokeColor: "transparent"
		fillColor: root.color

		PathPolyline {
			path: {
				const list = [];

				for (let i = 0; i < root.outline.length; i += 2)
					list.push(Qt.point(root.outline[i], root.outline[i + 1]));

				return list;
			}
		}
	}
}
