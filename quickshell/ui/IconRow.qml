import QtQuick
import qs
import qs.services
import qs.ui

Item {
	id: row

	required property var model
	property int index: 0
	property int columns: 1
	property real cell: Config.windowsGridCell
	property real iconSize: Config.windowsIconSize
	property real highlightSize: Config.windowsHighlightSize
	property real labelSize: Config.windowsTitleSize
	property string emptyMessage: ""

	readonly property int count: row.model ? row.model.length : 0
	readonly property int active: row.count === 0 ? -1 : Util.clamp(row.index, 0, row.count - 1)
	readonly property real emptyWidth: row.count === 0 ? emptyLabel.implicitWidth : 0

	implicitWidth: Math.max(row.columns * row.cell, row.emptyWidth)
	implicitHeight: Math.ceil(Math.max(row.count, 1) / row.columns) * row.cell + Config.windowsLabelGap + labelText.implicitHeight

	Item {
		id: grid

		width: Math.max(row.columns * row.cell, row.emptyWidth)
		height: Math.ceil(Math.max(row.count, 1) / row.columns) * row.cell
		clip: true

		Highlight {
			fillParent: false
			active: row.active >= 0
			x: (row.active % row.columns) * row.cell + (row.cell - row.highlightSize) / 2
			y: Math.floor(row.active / row.columns) * row.cell + (row.cell - row.highlightSize) / 2
			width: row.highlightSize
			height: row.highlightSize
		}

		Repeater {
			model: row.model

			delegate: Item {
				id: cellItem

				required property var modelData
				required property int index

				readonly property string appIcon: modelData.appId !== undefined && modelData.appId !== "" ? AppIcons.iconOf(modelData.appId) : ""

				x: (cellItem.index % row.columns) * row.cell
				y: Math.floor(cellItem.index / row.columns) * row.cell
				width: row.cell
				height: row.cell

				AppIcon {
					anchors.centerIn: parent
					implicitSize: row.iconSize
					visible: cellItem.appIcon !== ""
					source: cellItem.appIcon
				}

				Text {
					anchors.centerIn: parent
					visible: cellItem.appIcon === "" && modelData.glyph !== undefined && modelData.glyph !== ""
					font.family: Config.fontFamily
					font.pixelSize: row.iconSize
					color: Config.foreground
					text: cellItem.modelData.glyph || ""
				}
			}
		}

		Text {
			id: emptyLabel

			anchors.centerIn: parent
			visible: row.count === 0
			font.family: Config.fontFamily
			font.pixelSize: Config.launcherFontSize
			color: Config.muted
			text: row.emptyMessage
		}
	}

	Text {
		id: labelText

		width: Math.min(implicitWidth, grid.width)
		x: row.active < 0 ? 0 : Util.clamp(row.active * row.cell + (row.cell - width) / 2, 0, grid.width - width)
		anchors.top: grid.bottom
		anchors.topMargin: Config.windowsLabelGap
		horizontalAlignment: Text.AlignHCenter
		elide: Text.ElideRight
		font.family: Config.fontFamily
		font.pixelSize: row.labelSize
		color: Config.foreground
		text: row.active >= 0 ? (row.model[row.active].name || "") : ""
	}
}
