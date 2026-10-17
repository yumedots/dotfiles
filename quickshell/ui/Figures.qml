import QtQuick
import QtQuick.Shapes
import qs

Shape {
	id: root

	property string figure: "squircle"
	property real morph: 0
	property int lobes: Config.figureLobes
	property real scallop: Config.figureScallop
	property color color: Config.foreground

	preferredRendererType: Shape.CurveRenderer

	readonly property var preset: Figure.figurePreset(root.figure)
	readonly property var outline: Figure.figurePoints({
		width: root.width,
		height: root.height,
		exponent: root.preset.exponent,
		lobes: root.lobes,
		scallop: root.scallop,
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
