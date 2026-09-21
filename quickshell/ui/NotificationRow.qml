import QtQuick
import qs
import qs.services

Item {
	id: root

	property var entry: null
	property bool selected: false
	property bool expanded: false
	property bool expandable: false

	readonly property real pad: Config.notifyRowPadding
	readonly property real inset: Config.notifyPadding + root.pad
	readonly property real cardHeight: Config.notifyVisibleRows * Config.notifyRowHeight
	readonly property color ink: hl.active ? Config.launcherHighlightText : Config.foreground
	readonly property color aside: root.expanded ? Config.foreground : (root.selected ? Config.launcherHighlightText : Config.dim)
	readonly property string picture: root.pictureOf()
	readonly property bool urgent: !!root.entry && root.entry.urgent === true
	readonly property string detail: root.entry ? Parse.plainText(root.entry.body) : ""
	readonly property string headline: root.entry ? (root.entry.summary !== "" ? root.entry.summary : root.entry.appName) : ""
	readonly property string message: root.entry ? (root.detail !== "" ? root.detail : root.entry.appName) : ""

	readonly property int bodyLines: root.expanded
		? 1000
		: Math.max(1, Math.floor((Config.notifyRowHeight - root.pad * 2 - titleMetrics.implicitHeight - lines.spacing) / bodyMetrics.implicitHeight))
	readonly property bool more: root.expandable && !root.expanded && measure.lineCount > root.bodyLines

	implicitHeight: root.expanded ? Math.max(root.cardHeight, lines.implicitHeight + root.pad * 2) : Config.notifyRowHeight
	clip: true
	opacity: root.entry && root.entry.gone === true ? Config.notifyGoneOpacity : 1

	function pictureOf() {
		if (!root.entry)
			return "";

		const image = root.entry.image || "";
		const icon = root.entry.icon || "";

		if (image.indexOf("/") === 0 || image.indexOf("https://") === 0 || image.indexOf("image://") === 0)
			return image;

		if (icon.indexOf("/") === 0)
			return icon;

		return AppIcons.iconOf(root.entry.desktopEntry, []);
	}

	Highlight {
		id: hl

		active: root.selected
	}

	Rectangle {
		anchors.left: parent.left
		anchors.top: parent.top
		anchors.bottom: parent.bottom
		width: 2
		color: Config.red
		visible: root.urgent
	}

	Rectangle {
		id: icon

		anchors.left: parent.left
		anchors.leftMargin: root.inset
		anchors.top: parent.top
		anchors.topMargin: root.pad
		width: Config.notifySlot
		height: Config.notifySlot
		color: "transparent"
		clip: true

		Text {
			anchors.centerIn: parent
			visible: avatar.status !== Image.Ready
			font.family: Config.fontFamily
			font.pixelSize: Config.notifyBellSize
			color: Config.foreground
			text: Config.iconBell
		}

		Image {
			id: avatar

			anchors.fill: parent
			source: root.picture
			fillMode: Image.PreserveAspectCrop
			visible: status === Image.Ready
		}
	}

	Column {
		id: lines

		anchors.left: icon.right
		anchors.leftMargin: Config.notifySlotGap
		anchors.right: parent.right
		anchors.rightMargin: root.inset + chevron.implicitWidth + Config.notifySlotGap
		anchors.top: parent.top
		anchors.topMargin: root.pad
		spacing: 2

		Text {
			width: lines.width
			elide: Text.ElideRight
			font.family: Config.fontFamily
			font.pixelSize: Config.fontSize
			color: root.ink
			text: root.headline
		}

		Text {
			id: body

			width: lines.width
			elide: Text.ElideRight
			wrapMode: Text.WordWrap
			maximumLineCount: root.bodyLines
			font.family: Config.fontFamily
			font.pixelSize: Config.notifyAppFontSize
			color: root.aside
			text: root.message
		}
	}

	Text {
		id: chevron

		anchors.right: parent.right
		anchors.rightMargin: root.inset
		anchors.verticalCenter: parent.verticalCenter
		visible: root.more
		font.family: Config.fontFamily
		font.pixelSize: Config.fontSize
		color: root.ink
		text: Config.iconRight
	}

	Text {
		id: titleMetrics

		visible: false
		font.family: Config.fontFamily
		font.pixelSize: Config.fontSize
		text: "0"
	}

	Text {
		id: bodyMetrics

		visible: false
		font.family: Config.fontFamily
		font.pixelSize: Config.notifyAppFontSize
		text: "0"
	}

	Text {
		id: measure

		width: body.width
		visible: false
		wrapMode: Text.WordWrap
		font.family: Config.fontFamily
		font.pixelSize: Config.notifyAppFontSize
		text: root.message
	}
}
