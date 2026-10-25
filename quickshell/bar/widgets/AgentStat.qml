import QtQuick
import qs
import qs.services
import qs.ui
import "../../tooltips"

// The agent face, rendered as a topbar widget.
//
// The face shows the state of the agent: idle, working, blocked, or
// error. It blinks on its own and keeps its eyes still, so the bar stays calm.
// Clicking the face opens a panel with a bigger face that does follow the
// cursor, the work that is going on, and the subscription the agent runs on.
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

	// The face is drawn as a solid body with the eyes punched out of it, so
	// the only transparent part of the icon is the eyes. The body is smaller
	// than the slot it is drawn in, so the slot is made larger to make up for
	// that and the face sits at the same height as the glyphs beside it.
	iconWidth: root.iconInkHeight / 0.86

	iconComponent: Component {
		AgentFace {
			// The face fills the icon slot, so it lines up with the font glyphs
			// next to it instead of floating above them.
			width: parent.width
			height: parent.height

			size: Math.min(parent.width, parent.height)
			state: Yudae.connected ? Yudae.state : "idle"

			// The bar icon keeps its eyes still. The panel face tracks the cursor.
			followCursor: false

			bodyColor: ink
			eyeColor: Config.surface
		}
	}

	popupContent: Component {
		AgentPanel {
			source: root
		}
	}

	// The panel sits against the right edge of the screen, the way the
	// panels of the other widgets on that side do.
	popupAlignRight: true

	// The panel is made when the bar is, so the face is already turning when
	// the panel opens instead of starting over.
	popupPreload: true
}
