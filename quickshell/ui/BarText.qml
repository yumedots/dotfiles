import QtQuick
import qs
import qs.services

Item {
	id: root

	property string text: ""
	property string inkId: ""
	property color color: BarInk.pick(root.bar, root.inkId, Config.foreground)
	property int pixelSize: Settings.fontSize
	property real padding: 0
	property var bar: null
	property var onActivate
	property bool popupKeyboard: true
	property bool popupAlignRight: false
	property bool popupCentered: false
	property bool popupAlwaysCentered: false
	property real popupPadding: -1
	property alias popupContent: popupWindow.contentSource

	readonly property real baselineLift: Math.ceil(Config.barThickness)
	readonly property alias popupVisible: popupWindow.shown

	function openPopup() {
		popupWindow.open();
	}

	function closePopup() {
		popupWindow.close();
	}

	function isPopupOpen() {
		return popupWindow.shown;
	}

	function clicked() {
		if (root.onActivate)
			root.onActivate();
		else if (root.bar)
			root.bar.activateWidget(root, root.popupKeyboard);
	}

	readonly property var sample: metrics.tightBoundingRect

	implicitWidth: label.implicitWidth + root.padding * 2
	implicitHeight: root.sample.height

	Tooltip {
		id: popupWindow

		anchorWindow: root.bar
		anchorItem: root
		contentPadding: root.popupPadding
		wantsKeyboard: root.popupKeyboard
		alignRight: root.popupAlignRight
		centered: root.popupCentered
		alwaysCentered: root.popupAlwaysCentered
	}

	TextMetrics {
		id: metrics
		font.family: Config.fontFamily
		font.pixelSize: root.pixelSize
		text: Config.valueSample
	}

	Text {
		id: label

		x: root.padding
		y: metrics.boundingRect.y - metrics.tightBoundingRect.y

		font.family: Config.fontFamily
		font.pixelSize: root.pixelSize
		color: root.color
		text: root.text

		Behavior on color {
			enabled: BarInk.fading
			ColorAnimation {
				duration: BarInk.fadeMs
			}
		}
	}

	MouseArea {
		anchors.fill: parent
		anchors.margins: -Config.barHitPadding

		onClicked: root.clicked()
	}
}
