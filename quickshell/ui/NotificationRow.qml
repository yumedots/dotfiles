import QtQuick
import qs
import qs.services

Item {
	id: root

	property var entry: null
	property bool selected: false
	property bool expanded: false
	property bool expandable: false
	property bool single: false

	readonly property real pad: Config.notifyRowPadding
	readonly property real inset: Config.notifyPadding + root.pad
	readonly property real cardHeight: Config.notifyVisibleRows * Config.notifyRowHeight
	readonly property color ink: hl.active ? Config.launcherHighlightText : Config.foreground
	readonly property color aside: root.expanded ? Config.foreground : (root.selected ? Config.launcherHighlightText : Config.muted)
	readonly property string picture: root.pictureOf()
	readonly property bool photo: root.entry !== null && String(root.entry.image || "") !== ""
	readonly property bool banner: root.photo && (root.expanded || root.single)
	readonly property real bannerExtra: photoBox.height > 0 ? photoBox.height + Config.notifyRowGap : 0
	readonly property bool urgent: !!root.entry && root.entry.urgent === true
	readonly property string detail: root.entry ? Parse.plainText(root.entry.body) : ""
	readonly property string headline: root.entry ? (root.entry.summary !== "" ? root.entry.summary : root.entry.appName) : ""
	readonly property string message: root.entry ? (root.detail !== "" ? root.detail : root.entry.appName) : ""

	readonly property int bodyLines: root.expanded
		? 1000
		: Math.max(1, Math.floor((Config.notifyRowHeight - root.pad * 2 - titleMetrics.implicitHeight - lines.spacing) / bodyMetrics.implicitHeight))
	readonly property bool more: root.expandable && !root.expanded && measure.lineCount > root.bodyLines

	implicitHeight: (root.expanded ? Math.max(root.cardHeight, lines.implicitHeight + root.pad * 2) : Config.notifyRowHeight) + root.bannerExtra
	clip: true
	opacity: root.entry && root.entry.gone === true ? Config.notifyGoneOpacity : 1


	function pictureOf() {
		if (!root.entry)
			return "";

		const image = root.entry.image || "";
		const icon = root.entry.icon || "";

		if (image.indexOf("image://icon/") === 0) {
			const path = image.slice(13);
			if (path.indexOf("/") === 0)
				return path;
			return AppIcons.iconOf(path);
		}

		if (image.indexOf("/") === 0 || image.indexOf("file://") === 0 || image.indexOf("https://") === 0 || image.indexOf("image://") === 0)
			return image;

		const file = icon.indexOf("file://") === 0 ? icon.slice(7) : icon;

		if (file.indexOf("/") === 0)
			return file;

		return AppIcons.iconOf(root.entry.desktopEntry, [file, root.entry.appName]);
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

	Item {
		id: photoBox

		anchors.left: parent.left
		anchors.leftMargin: root.inset
		anchors.right: parent.right
		anchors.rightMargin: root.inset
		anchors.top: parent.top
		anchors.topMargin: root.pad
		height: root.banner && artwork.status === Image.Ready ? Config.notifyImageMax : 0

		Rectangle {
			anchors.fill: parent
			color: Config.launcherSearchBox
		}

		Image {
			id: artwork

			anchors.fill: parent
			source: root.picture
			sourceSize.width: photoBox.width > 0 ? Math.round(photoBox.width * 2) : -1
			cache: false
			fillMode: Image.PreserveAspectFit
			visible: status === Image.Ready
		}

		Rectangle {
			anchors.fill: parent
			color: "transparent"
			border.width: 1
			border.color: Config.dim
		}
	}

	Rectangle {
		id: icon

		anchors.left: parent.left
		anchors.leftMargin: root.inset
		anchors.top: photoBox.height > 0 ? photoBox.bottom : parent.top
		anchors.topMargin: photoBox.height > 0 ? Config.notifyRowGap : root.pad
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
			sourceSize.width: Config.notifySlot * 3
			cache: false
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
		anchors.top: photoBox.height > 0 ? photoBox.bottom : parent.top
		anchors.topMargin: photoBox.height > 0 ? Config.notifyRowGap : root.pad
		spacing: 2

		Text {
			width: lines.width
			elide: Text.ElideRight
			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
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
		anchors.verticalCenter: lines.verticalCenter
		visible: root.more
		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
		color: root.ink
		text: Config.iconRight
	}

	Text {
		id: titleMetrics

		visible: false
		font.family: Config.fontFamily
		font.pixelSize: Settings.fontSize
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
