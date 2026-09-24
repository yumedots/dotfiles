import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

PanelWindow {
	id: root

	default property alias content: border.content

	property Item anchorItem
	property var anchorWindow
	property var borderColors: null
	property real borderWidth: -1
	property bool wantsKeyboard: false
	property bool alignRight: false
	property real contentPadding: -1

	property real anchorX: 0
	property bool shown: false

	readonly property bool shut: !root.shown
	readonly property bool revealed: root.shown

	// ponytail: a popup that takes exclusive keyboard focus makes hyprland send it
	// every click, so it has to cover the bar strip as well: a click there is
	// handed to the widget under the pointer instead of being swallowed, which is
	// what makes one widget swap for another with a single click. Popups that do
	// not want the keyboard stay card sized and let the bar take its own clicks.
	// Ceiling: the band under the bar swallows clicks aimed at apps underneath.
	readonly property bool wide: root.wantsKeyboard && !root.shut
	readonly property bool atBottom: root.anchorWindow !== null && root.anchorWindow.atBottom === true
	readonly property real outerMargin: root.anchorWindow !== null ? root.anchorWindow.outerMargin : border.gapsOut
	readonly property real wantedX: root.anchorX + (root.anchorItem ? root.anchorItem.width : 0) / 2 - root.cardWidth / 2
	readonly property real limitX: (root.anchorWindow ? root.anchorWindow.width : 0) - root.cardWidth
	readonly property real hang: Math.round(border.gapsOut + Config.tooltipOffsetY)
	readonly property real screenWidth: root.screen ? root.screen.width : root.cardWidth
	readonly property real screenHeight: root.screen ? root.screen.height : root.cardHeight
	readonly property real barReserve: root.outerMargin + (root.anchorWindow ? root.anchorWindow.implicitHeight : 0)

	screen: root.anchorWindow ? root.anchorWindow.screen : null

	readonly property real scale: border.scale
	readonly property real cardWidth: Util.snap(border.contentWidth + 2 * border.inset, root.scale)
	readonly property real cardHeight: Util.snap(border.contentHeight + 2 * border.inset, root.scale)
	readonly property real cardX: Util.snap(root.alignRight
		? root.screenWidth - root.cardWidth - root.outerMargin
		: root.outerMargin + Util.clamp(root.wantedX + Config.tooltipOffsetX, 0, root.limitX), root.scale)
	readonly property real cardY: root.atBottom
		? Math.round(root.screenHeight - root.barReserve - root.hang - root.cardHeight)
		: Math.round(root.barReserve + root.hang)

	// ponytail: the surface is the whole screen and never changes size, so opening
	// one can neither re-create it (that churn leaks a sync_file fd per cycle) nor
	// resize it. A card sized surface grew with its content every time the popup
	// filled in, and hyprland shows the frame it already has stretched over the new
	// size, which is what smeared on screen. While closed it parks under the screen
	// with nothing drawn in it. Ceiling: a screen sized buffer stays mapped per popup.
	// exclusiveZone -1 places it against the monitor, not the bar's reserved strip.
	anchors.top: !root.atBottom
	anchors.bottom: root.atBottom
	anchors.left: true

	exclusiveZone: -1

	margins.top: root.shut && !root.atBottom ? root.screenHeight : 0
	margins.bottom: root.shut && root.atBottom ? root.screenHeight : 0
	margins.left: 0

	implicitWidth: root.screenWidth
	implicitHeight: root.screenHeight

	color: "transparent"

	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "tooltip"
	WlrLayershell.keyboardFocus: root.wantsKeyboard && root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

	function refreshAnchor() {
		if (root.anchorItem === null || root.anchorWindow === null)
			return;

		root.anchorX = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0).x;
	}

	function open() {
		root.refreshAnchor();
		root.shown = true;
	}

	function close() {
		root.shown = false;
	}

	function toggle() {
		if (root.shown)
			root.close();
		else
			root.open();
	}

	function insideCard(x, y) {
		return x >= root.cardLeft && x <= root.cardLeft + root.cardWidth && y >= root.cardTop && y <= root.cardTop + root.cardHeight;
	}

	function forwarded(x, y) {
		const bar = root.anchorWindow;

		if (bar && typeof bar.clickAt === "function")
			bar.clickAt(x, y);
		else
			root.close();
	}

	readonly property real cardLeft: root.cardX
	readonly property real cardTop: root.cardY

	MouseArea {
		id: backdrop

		anchors.fill: parent
		visible: root.wide
		acceptedButtons: Qt.AllButtons

		onPressed: function (mouse) {
			if (root.insideCard(mouse.x, mouse.y))
				return;

			root.forwarded(mouse.x, mouse.y);
		}
	}

	Item {
		id: card

		x: root.cardLeft
		y: root.cardTop
		width: root.cardWidth
		height: root.cardHeight

		HyprBorder {
			id: border

			anchors.fill: parent
			padding: root.contentPadding >= 0 ? root.contentPadding : border.gapsIn
			borderColors: root.borderColors
			borderWidth: root.borderWidth
			borderOpacity: 1
			visible: root.revealed

			Keys.onPressed: function (event) {
				if (!Input.cancel(event))
					return;

				root.close();
				event.accepted = true;
			}
		}

		Text {
			id: closeButton

			anchors.right: parent.right
			anchors.top: parent.top
			anchors.margins: Config.tooltipCloseInset
			visible: root.revealed
			font.family: Config.fontFamily
			font.pixelSize: Config.tooltipCloseSize
			color: closeHit.containsMouse ? Config.foreground : Config.muted
			text: Config.iconClose

			MouseArea {
				id: closeHit

				anchors.fill: parent
				anchors.margins: -Config.tooltipCloseSize / 3
				hoverEnabled: true

				onClicked: root.close()
			}
		}
	}
}
