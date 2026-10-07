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
	property bool preload: false
	property bool slideExit: false
	property bool alignRight: false
	property bool fullscreen: false
	property bool closable: true
	property real contentPadding: -1
	property Component contentSource: null

	property real anchorX: 0
	property bool shown: false

	readonly property bool shut: !root.shown && card.opacity === 0

	readonly property bool wide: root.wantsKeyboard && !root.shut
	readonly property bool atBottom: root.anchorWindow !== null && root.anchorWindow.atBottom === true
	readonly property real outerMargin: root.anchorWindow !== null ? root.anchorWindow.outerMargin : Config.gapsOut
	readonly property real wantedX: root.anchorX + (root.anchorItem ? root.anchorItem.width : 0) / 2 - root.cardWidth / 2
	readonly property real limitX: (root.anchorWindow ? root.anchorWindow.width : 0) - root.cardWidth - Config.tooltipGap - Config.tooltipGapRight
	readonly property real hang: Config.tooltipHang
	readonly property real screenWidth: root.screen ? root.screen.width : root.cardWidth
	readonly property real screenHeight: root.screen ? root.screen.height : root.cardHeight
	readonly property real barReserve: root.outerMargin + (root.anchorWindow ? root.anchorWindow.implicitHeight : 0)

	screen: root.anchorWindow ? root.anchorWindow.screen : null

	readonly property real scale: border.scale
	readonly property real cardWidth: Util.snap(border.contentWidth + 2 * border.inset, root.scale)
	readonly property real cardHeight: Util.snap(border.contentHeight + 2 * border.inset, root.scale)
	readonly property real restX: root.screenWidth - root.cardWidth
	readonly property real restY: root.screenHeight - root.cardHeight
	readonly property bool posLeft: Config.popupPos.indexOf("left") >= 0
	readonly property bool posRight: Config.popupPos.indexOf("right") >= 0
	readonly property bool posBottom: Config.popupPos.indexOf("bottom") >= 0
	readonly property bool slideBelow: Config.popupY >= 0 ? Config.popupY > root.restY / 2 : root.posBottom
	readonly property real floatX: Config.popupX >= 0
		? Util.clamp(Config.popupX, 0, root.restX)
		: root.posRight ? root.restX - Config.gapsOut
			: root.posLeft ? Config.gapsOut
				: root.restX / 2
	readonly property real floatY: Config.popupY >= 0
		? Util.clamp(Config.popupY, 0, root.restY)
		: root.posBottom ? root.restY - Config.gapsOut
			: Config.gapsOut
	readonly property real cardX: root.fullscreen
		? Util.snap(root.floatX, root.scale)
		: Util.snap(root.alignRight
			? root.screenWidth - root.cardWidth - root.outerMargin - Config.tooltipGapRight
			: root.outerMargin + Config.tooltipGap + Util.clamp(root.wantedX + Config.tooltipOffsetX, 0, root.limitX), root.scale)
	readonly property real cardY: root.fullscreen
		? Math.round(root.floatY)
		: root.atBottom
			? Math.round(root.screenHeight - root.barReserve - root.hang - root.cardHeight)
			: Math.round(root.barReserve + root.hang)
	readonly property real slideX: root.screenWidth

	visible: root.shown || (root.slideExit ? card.sliding : card.opacity > 0)

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

	Region {
		id: cardRegion

		item: card
	}

	mask: root.wantsKeyboard ? null : cardRegion

	function refreshAnchor() {
		if (root.anchorItem === null || root.anchorWindow === null)
			return;

		root.anchorX = root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0).x;
	}

	function open() {
		root.refreshAnchor();
		root.shown = true;

		if (root.slideExit) {
			slideAnim.stop();
			card.slideOffset = 0;
		}

		Qt.callLater(function () {
			const first = border.content.length > 0 ? border.content[0] : null;
			const target = first && first.item ? first.item : (first || border);

			target.forceActiveFocus();
		});
	}

	function close() {
		if (root.slideExit && !slideAnim.running)
			slideAnim.restart();

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

		property real slideOffset: 0
		readonly property bool sliding: slideAnim.running

		x: root.cardLeft + card.slideOffset
		y: root.fullscreen && !root.shown ? (root.slideBelow ? root.screenHeight : -root.cardHeight) : root.cardTop
		width: root.cardWidth
		height: root.cardHeight
		opacity: root.shown || (root.slideExit && sliding) ? 1 : 0

		Behavior on y {
			enabled: root.fullscreen

			NumberAnimation { duration: Config.popupFadeMs; easing.type: Easing.InOutCubic }
		}

		Behavior on opacity {
			NumberAnimation { duration: Config.popupFadeMs; easing.type: Easing.OutCubic }
		}

		HyprBorder {
			id: border

			focus: true
			anchors.fill: parent
			padding: root.contentPadding >= 0 ? root.contentPadding : Config.gapsIn
			borderColors: root.borderColors
			borderWidth: root.borderWidth
			borderOpacity: 1

			Keys.onPressed: function (event) {
				if (!Input.cancel(event))
					return;

				root.close();
				event.accepted = true;
			}

			Loader {
				sourceComponent: root.contentSource
				active: root.contentSource !== null && (root.preload || root.shown || card.opacity > 0)
			}
		}

		NumberAnimation {
			id: slideAnim

			target: card
			property: "slideOffset"
			from: 0
			to: root.slideX - root.cardX
			duration: Config.popupSlideMs
			easing.type: Easing.InOutCubic
		}

		Text {
			id: closeButton

			visible: root.closable && !root.fullscreen
			anchors.right: parent.right
			anchors.top: parent.top
			anchors.margins: Config.tooltipCloseInset
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
