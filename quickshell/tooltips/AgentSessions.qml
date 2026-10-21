import QtQuick
import qs
import qs.services
import qs.ui

// The sessions the agent knows about.
//
// The ones with work in them come first, each with a glyph that says what is
// happening: a braille spinner while it works, a question mark when it is asking
// something, and a checkmark when it is done. The rest are shown in grey, most
// recently touched first.
Item {
	id: root

	property var active: []
	property var inactive: []
	property string target: ""
	property string modelName: ""
	property var models: []
	property string modelError: ""

	signal sessionChosen(string id)
	signal modelChosen(string id, var model)

	// How many sessions are shown at once. The rest are folded away.
	property int limit: 8

	readonly property var shownActive: root.active.slice(0, root.limit)
	readonly property var shownInactive: root.inactive.slice(0, Math.max(0, root.limit - root.shownActive.length))

	// How many sessions are not shown.
	readonly property int hiddenCount: root.active.length + root.inactive.length
		- root.shownActive.length - root.shownInactive.length

	readonly property int rowHeight: Settings.fontSize + 8
	readonly property real glyphSize: Settings.fontSize + 2

	// How much room the directory takes on the right.
	readonly property real directoryWidth: 74

	// The colour of a row, which is brighter when the row is the one the
	// panel is talking to.
	function rowColor(modelData, base) {
		return modelData.id === root.target ? Config.foreground : base;
	}

	implicitWidth: Config.agentPanelWidth
	implicitHeight: (root.shownActive.length + root.shownInactive.length) * root.rowHeight
		+ (root.models.length > 0 ? root.rowHeight + 6 : 0)
		+ (root.hiddenCount > 0 ? root.rowHeight : 0)

	Column {
		id: stack

		anchors.fill: parent
		spacing: 0

		Repeater {
			model: root.shownActive

			delegate: Item {
				required property var modelData
				required property int index

				width: stack.width
				height: root.rowHeight

				readonly property bool isTarget: modelData.id === root.target

				// The row the panel is talking to is marked, so it is clear
				// which session a message will go to.
				Rectangle {
					visible: parent.isTarget
					anchors.fill: parent
					anchors.leftMargin: -4
					anchors.rightMargin: -4
					radius: 3
					color: Config.launcherHighlight
				}

				Text {
					id: glyph

					x: 0
					anchors.verticalCenter: parent.verticalCenter

					width: 14
					horizontalAlignment: Text.AlignHCenter

					font.family: Config.fontFamily
					font.pixelSize: root.glyphSize
					color: modelData.question ? Config.red : (modelData.failed ? Config.red : (parent.isTarget ? Config.foreground : Config.muted))
					text: modelData.question ? Config.agentIconQuestion : (modelData.failed ? Config.agentIconClose : Config.agentIconWorking)
				}

				Text {
					x: 18
					y: 0
					width: parent.width - 18 - root.directoryWidth
					height: parent.height
					verticalAlignment: Text.AlignVCenter
					elide: Text.ElideMiddle

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: parent.isTarget ? Config.foreground : Config.muted
					text: modelData.title || modelData.id
				}

				Text {
					anchors.right: parent.right
					y: 0
					width: root.directoryWidth
					height: parent.height
					horizontalAlignment: Text.AlignRight
					verticalAlignment: Text.AlignVCenter
					elide: Text.ElideLeft

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: parent.isTarget ? Config.muted : Config.dim
					text: modelData.directory ? modelData.directory.split("/").pop() : ""
				}

				MouseArea {
					anchors.fill: parent
					onClicked: root.sessionChosen(modelData.id)
				}
			}
		}

		Repeater {
			model: root.shownInactive

			delegate: Item {
				required property var modelData
				required property int index

				width: stack.width
				height: root.rowHeight

				readonly property bool isTarget: modelData.id === root.target

				// The row the panel is talking to is marked, so it is clear
				// which session a message will go to.
				Rectangle {
					visible: parent.isTarget
					anchors.fill: parent
					anchors.leftMargin: -4
					anchors.rightMargin: -4
					radius: 3
					color: Config.launcherHighlight
				}

				Text {
					id: glyph

					x: 0
					anchors.verticalCenter: parent.verticalCenter

					width: 14
					horizontalAlignment: Text.AlignHCenter

					font.family: Config.fontFamily
					font.pixelSize: root.glyphSize
					color: parent.isTarget ? Config.foreground : Config.dim
					text: Config.agentIconDone
				}

				Text {
					x: 18
					y: 0
					width: parent.width - 18 - root.directoryWidth
					height: parent.height
					verticalAlignment: Text.AlignVCenter
					elide: Text.ElideMiddle

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: parent.isTarget ? Config.foreground : Config.dim
					text: modelData.title || modelData.id
				}

				Text {
					anchors.right: parent.right
					y: 0
					width: root.directoryWidth
					height: parent.height
					horizontalAlignment: Text.AlignRight
					verticalAlignment: Text.AlignVCenter
					elide: Text.ElideLeft

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: parent.isTarget ? Config.muted : Config.dim
					text: modelData.directory ? modelData.directory.split("/").pop() : ""
				}

				MouseArea {
					anchors.fill: parent
					onClicked: root.sessionChosen(modelData.id)
				}
			}
		}

		// How many sessions are folded away.
		Item {
			visible: root.hiddenCount > 0
			width: stack.width
			height: root.rowHeight

			Text {
				x: 18
				y: 0
				width: parent.width - 18
				height: parent.height
				verticalAlignment: Text.AlignVCenter

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.dim
				text: "+" + root.hiddenCount + " more"
			}

			MouseArea {
				anchors.fill: parent
				onClicked: root.limit = root.limit + 8
			}
		}

		// The model of the session, and the other models to pick from.
		Item {
			visible: root.models.length > 0
			width: stack.width
			height: root.rowHeight + 6

			Row {
				id: modelRow

				anchors.left: parent.left
				anchors.top: parent.top
				anchors.topMargin: 6
					spacing: 4

				Text {
					id: modelLabel

					anchors.verticalCenter: modelToggle.verticalCenter
					width: Math.min(implicitWidth, stack.width - 20)
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: root.modelError !== "" ? Config.red : Config.muted
					text: root.modelName
				}

				Text {
					id: modelToggle

					width: 10
					anchors.verticalCenter: parent.verticalCenter

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: Config.dim
					text: Config.agentIconDown

					MouseArea {
						anchors.fill: parent
						anchors.margins: -4
						onClicked: modelList.visible = !modelList.visible
					}
				}
			}
		}
	}

	// The other models, folded away until the model is picked.
	Column {
		id: modelList

		visible: false
		x: 0
		y: stack.height
		width: stack.width
		spacing: 0

		Rectangle {
			width: modelList.width
			height: modelList.children.length * root.rowHeight
			color: Config.surfaceTranslucent
		}

		Repeater {
			model: root.models

			delegate: Item {
				required property var modelData
				required property int index

				width: modelList.width
				height: root.rowHeight

				Text {
					x: 4
					y: 0
					width: parent.width - 8
					height: parent.height
					verticalAlignment: Text.AlignVCenter
					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: Config.foreground
					text: modelData.providerID + "/" + modelData.name
				}

				MouseArea {
					anchors.fill: parent
					onClicked: {
						modelList.visible = false;
						root.modelChosen(root.target, modelData);
					}
				}
			}
		}
	}
}
