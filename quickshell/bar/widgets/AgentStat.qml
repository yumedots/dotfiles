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
	iconWidth: Config.agentBarFaceSize

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
