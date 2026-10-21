import QtQuick
import qs
import qs.services
import qs.ui
import "../../tooltips"

// The agent face, rendered as a topbar widget.
//
// The face shows the state of the OpenCode agent: idle, working, blocked, or
// error. It blinks on its own and keeps its eyes still, so the bar stays calm.
// Clicking the face opens a panel with a bigger face that does follow the
// cursor, the agent's session, and an input line to send it a message.
BarStat {
	id: root

	inkId: "agent"

	mode: "icon"
	showBar: false

	// The face has no bar under it, so the stat is shorter than the others.
	// The row is aligned by the bottom, so the face would sit lower than the
	// glyphs beside it. Lifting it by the thickness of the bar puts it back on
	// the same line.
	readonly property real baselineLift: Math.ceil(Config.barThickness)

	// The face is drawn as an outline, the way the other icons in the bar are
	// drawn, and it is given the same height as their ink, so it sits in the
	// bar like one of them instead of as a solid blob beside them.
	//
	// The body of the face is smaller than the slot it is drawn in, and the
	// outline around it is a pixel wide, so the slot is made larger to make up
	// for both.
	iconWidth: (root.iconInkHeight - 1) / 0.86

	iconComponent: Component {
		AgentFace {
			// The face fills the icon slot, so it lines up with the font glyphs
			// next to it instead of floating above them.
			width: parent.width
			height: parent.height

			size: Math.min(parent.width, parent.height)
			state: OpenCode.state

			// The bar icon keeps its eyes still. The panel face tracks the cursor.
			followCursor: false

			// The bar draws thin outlines, so the face is hollow here.
			hollow: true

			bodyColor: ink
			eyeColor: Config.surface
		}
	}

	popupContent: Component {
		AgentPanel {
			source: root
			onCloseRequested: root.closePopup()
		}
	}
}
