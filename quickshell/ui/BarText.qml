import QtQuick
import qs

Item {
	id: root

	property string text: ""
	property color color: Config.foreground
	property int pixelSize: Config.fontSize
	property real padding: 0
	property var bar: null
	property var onActivate
	property bool popupKeyboard: true
	property bool popupAlignRight: false
	property real popupPadding: -1
	property alias popupContent: popupWindow.content

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

	readonly property var sampleInk: metrics.tightBoundingRect

	implicitWidth: label.implicitWidth + root.padding * 2
	implicitHeight: root.sampleInk.height

	Tooltip {
		id: popupWindow

		anchorWindow: root.bar
		anchorItem: root
		contentPadding: root.popupPadding
		wantsKeyboard: root.popupKeyboard
		alignRight: root.popupAlignRight
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
	}

	MouseArea {
		anchors.fill: parent
		anchors.margins: -Config.barHitPadding

		onClicked: root.clicked()
	}
}
