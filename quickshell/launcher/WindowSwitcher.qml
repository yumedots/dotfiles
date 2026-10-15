import QtQuick
import qs
import qs.ui
import qs.services

Item {
	id: switcher

	required property var results
	required property var entries
	required property int index
	required property string title
	required property string emptyMessage
	required property real available

	readonly property real cell: Config.windowsGridCell
	readonly property int count: switcher.results.length
	readonly property int columns: Math.max(1, Math.min(switcher.count, Math.floor((switcher.available - Config.windowsRowMargin) / switcher.cell)))
	readonly property real emptyWidth: switcher.count === 0 ? emptyText.implicitWidth : 0

	implicitWidth: grid.width
	implicitHeight: grid.height + Config.windowsLabelGap + windowName.height

	Item {
		id: grid

		width: Math.max(switcher.columns * switcher.cell, switcher.emptyWidth)
		height: Math.ceil(Math.max(switcher.count, 1) / switcher.columns) * switcher.cell
		clip: true

		Highlight {
			fillParent: false
			active: switcher.count > 0
			x: (switcher.index % switcher.columns) * switcher.cell + (switcher.cell - Config.windowsHighlightSize) / 2
			y: Math.floor(switcher.index / switcher.columns) * switcher.cell + (switcher.cell - Config.windowsHighlightSize) / 2
			width: Config.windowsHighlightSize
			height: Config.windowsHighlightSize
		}

		Repeater {
			model: switcher.results

			delegate: Item {
				id: iconCell

				required property var modelData
				required property int index

				readonly property string icon: modelData.appId !== undefined && modelData.appId !== "" ? AppIcons.iconOf(modelData.appId) : ""
				x: (iconCell.index % switcher.columns) * switcher.cell
				y: Math.floor(iconCell.index / switcher.columns) * switcher.cell
				width: switcher.cell
				height: switcher.cell

				AppIcon {
					anchors.centerIn: parent
					implicitSize: Config.windowsIconSize
					visible: iconCell.icon !== ""
					source: iconCell.icon
				}
			}
		}

		Text {
			id: emptyText

			anchors.centerIn: parent
			visible: switcher.count === 0
			font.family: Config.fontFamily
			font.pixelSize: Config.launcherFontSize
			color: Config.muted
			text: switcher.emptyMessage
		}
	}

	Item {
		opacity: 0
		width: 0
		height: 0

		Repeater {
			model: switcher.entries

			delegate: AppIcon {
				required property var modelData

				implicitSize: Config.windowsIconSize
				source: modelData.appId ? AppIcons.iconOf(modelData.appId) : ""
			}
		}
	}

	Text {
		id: windowName

		width: Math.min(implicitWidth, grid.width)
		x: Util.clamp(switcher.index * switcher.cell + (switcher.cell - width) / 2, 0, grid.width - width)
		anchors.top: grid.bottom
		anchors.topMargin: Config.windowsLabelGap
		horizontalAlignment: Text.AlignHCenter
		elide: Text.ElideRight
		font.family: Config.fontFamily
		font.pixelSize: Config.windowsTitleSize
		color: Config.foreground
		text: switcher.title
	}
}
