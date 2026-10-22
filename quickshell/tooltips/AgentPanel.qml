import QtQuick
import Quickshell
import qs
import qs.services
import qs.ui

// The agent panel: the face at full size, the state of the agent, the work
// that is going on, and the plan the agent runs on.
//
// The panel keeps one size, so the popup it lives in never changes size
// while it is open.
Item {
	id: root

	property var source: null

	// The marks are drawn at the size of the screen, so a small svg stays
	// sharp instead of being scaled up from a small raster.
	readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1

	readonly property string state: OpenCode.state
	readonly property string stateText: root.state === "working"
		? Config.agentWorkingText
		: root.state === "blocked"
			? Config.agentBlockedText
			: root.state === "error"
				? Config.agentErrorText
				: Config.agentIdleText

	// The face sits in the popup's own window, which covers the screen, so the
	// pointer is tracked against the panel's position on that screen.
	readonly property point faceCenter: {
		const win = root.Window.window;

		if (!win)
			return Qt.point(0, 0);

		const at = root.mapToItem(win.contentItem, 0, 0);
		const screen = root.source && root.source.bar ? root.source.bar.screen : null;
		const originX = screen ? screen.x : 0;
		const originY = screen ? screen.y : 0;

		return Qt.point(originX + at.x + root.width / 2, originY + at.y);
	}

	readonly property real gazeX: {
		if (!Cursor.valid)
			return 0;

		return Util.clamp((Cursor.x - root.faceCenter.x) / Config.agentFaceSize, -1, 1);
	}

	readonly property real gazeY: {
		if (!Cursor.valid)
			return 0;

		return Util.clamp((Cursor.y - root.faceCenter.y) / Config.agentFaceSize, -1, 1);
	}

	// The height of one row of work.
	readonly property real rowHeight: Settings.fontSize + 6

	// The braille spinner, which turns while a session works.
	readonly property var braille: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

	// The frame of the spinner. Every row starts at its own frame, so the
	// spinners do not turn in lockstep.
	property int spinFrame: 0

	implicitWidth: Config.agentPanelWidth + 2 * Config.agentPanelPadding
	implicitHeight: Config.agentPanelHeight + 2 * Config.agentPanelPadding

	clip: true

	// The clock the countdowns read, so a panel that sits open does not keep
	// showing a reset time that has already gone by.
	property real now: Date.now()

	Timer {
		interval: 30000
		repeat: true
		running: true
		triggeredOnStart: true

		onTriggered: root.now = Date.now()
	}

	// The spinner turns while a session works.
	Timer {
		interval: 90
		repeat: true
		running: true
		triggeredOnStart: true

		onTriggered: root.spinFrame = (root.spinFrame + 1) % 10
	}

	// How long until a window of the allowance resets, as a short phrase.
	function countdown(text) {
		const at = Date.parse(String(text || ""));

		if (!isFinite(at))
			return "";

		const minutes = Math.floor((at - root.now) / 60000);

		if (minutes <= 0)
			return "now";

		const days = Math.floor(minutes / 1440);
		const hours = Math.floor((minutes % 1440) / 60);

		if (days > 0)
			return days + "d " + hours + "h";

		if (hours > 0)
			return hours + "h " + (minutes % 60) + "m";

		return (minutes % 60) + "m";
	}

	// The face.
	Item {
		id: faceBox

		anchors.top: parent.top
		anchors.topMargin: Config.agentPanelPadding
		anchors.horizontalCenter: parent.horizontalCenter

		width: Config.agentFaceSize
		height: Config.agentFaceSize

		AgentFace {
			anchors.fill: parent

			size: Config.agentFaceSize
			state: root.state
			followCursor: true
			gazeX: root.gazeX
			gazeY: root.gazeY

			bodyColor: Config.foreground
			eyeColor: Config.surface
		}
	}

	// The state of the agent, and what it is asking about.
	Column {
		id: stateBox

		anchors.top: faceBox.bottom
		anchors.topMargin: Config.agentPanelPadding
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.leftMargin: Config.agentPanelPadding
		anchors.rightMargin: Config.agentPanelPadding

		spacing: 2

		Text {
			width: parent.width
			elide: Text.ElideRight

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: Config.foreground
			text: Config.agentPanelTitle
		}

		Text {
			width: parent.width
			elide: Text.ElideRight

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: root.state === "error" ? Config.red : Config.muted
			text: OpenCode.connected ? root.stateText : "OpenCode offline"
		}

		Text {
			width: parent.width
			visible: text !== ""
			elide: Text.ElideRight

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: Config.muted
			text: OpenCode.detailText
		}
	}

	// The plan the agent runs on, and how much of it is left.
	Column {
		id: planBox

		anchors.bottom: parent.bottom
		anchors.bottomMargin: Config.agentPanelPadding
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.leftMargin: Config.agentPanelPadding
		anchors.rightMargin: Config.agentPanelPadding

		spacing: 6

		Text {
			width: parent.width

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: Config.muted
			text: Config.agentPlanTitle
		}

		// The mark of the plan, with its name.
		Row {
			visible: OpenCode.limits.length > 0
			spacing: 6

			Image {
				width: 15
				height: 15

				source: "file://" + Quickshell.shellDir + "/assets/providers/" + Config.agentPlanIcon + ".svg"
				sourceSize.width: Math.round(15 * root.dpr)
				sourceSize.height: Math.round(15 * root.dpr)
				fillMode: Image.PreserveAspectFit
			}

			Text {
				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.foreground
				text: Config.agentPlanName
			}
		}

		Repeater {
			model: OpenCode.limits

			delegate: Item {
				id: limitRow

				required property var modelData

				width: parent.width
				height: Math.max(limitLabel.implicitHeight, limitReset.implicitHeight)

				readonly property bool alarming: modelData.percent >= 90

				// The label and the numbers are fixed columns, so every bar
				// starts and ends in the same place. The percentage sits
				// before the bar, so the bar is read as the rest.
				Text {
					id: limitLabel

					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					width: 60

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: Config.foreground
					text: modelData.title
				}

				Text {
					id: limitValue

					anchors.left: limitLabel.right
					anchors.verticalCenter: parent.verticalCenter
					width: 34

					horizontalAlignment: Text.AlignRight

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: limitRow.alarming ? Config.red : Config.muted
					text: Math.round(modelData.percent) + "%"
				}

				StepBar {
					id: limitMeter

					anchors.left: limitValue.right
					anchors.right: limitReset.left
					anchors.leftMargin: 8
					anchors.rightMargin: 10
					anchors.verticalCenter: parent.verticalCenter

					level: modelData.percent / 100
					ink: limitRow.alarming ? Config.red : Config.foreground
					track: Config.dim
				}

				Text {
					id: limitReset

					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					width: 54

					horizontalAlignment: Text.AlignRight

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: Config.muted
					text: root.countdown(modelData.resetsAt)
				}
			}
		}

		Text {
			width: parent.width
			visible: OpenCode.limits.length === 0 && OpenCode.usageError !== ""
			elide: Text.ElideRight

			font.family: Config.fontFamily
			font.pixelSize: Settings.fontSize
			color: Config.muted
			text: OpenCode.usageError
		}
	}

	// The work: what is going on now, and what is done.
	//
	// The side picks which of the two is shown, so the finished work does not
	// push the work that is going on around.
	Item {
		id: workBox

		visible: OpenCode.working.length > 0 || OpenCode.doneSessions.length > 0

		anchors.top: stateBox.bottom
		anchors.topMargin: Config.agentPanelPadding
		anchors.bottom: planBox.top
		anchors.bottomMargin: Config.agentPanelPadding
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.leftMargin: Config.agentPanelPadding
		anchors.rightMargin: Config.agentPanelPadding

		// The side that picks between the work and the finished work.
		Selector {
			id: sections

			anchors.left: parent.left
			anchors.top: parent.top
			anchors.bottom: parent.bottom

			width: 52
			visibleRows: 2
			rowHeight: root.rowHeight
			rowSpacing: 2

			model: [{ label: Config.agentWorkTitle, count: OpenCode.working.length }, { label: Config.agentDoneTitle, count: OpenCode.doneSessions.length }]
			currentIndex: 0

			delegate: Item {
				id: section

				required property var modelData
				required property int index

				width: ListView.view.rowWidth
				height: ListView.view.rowHeight

				Highlight {
					active: sections.currentIndex === section.index
				}

				Text {
					anchors.verticalCenter: parent.verticalCenter
					width: parent.width

					elide: Text.ElideRight

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: sections.currentIndex === section.index ? Config.foreground : Config.muted
					text: section.modelData.label
				}

				Text {
					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: Config.muted
					text: section.modelData.count
				}

				MouseArea {
					anchors.fill: parent

					onClicked: sections.currentIndex = section.index
				}
			}
		}

		// The line that splits the side from the work.
		Rectangle {
			anchors.left: sections.right
			anchors.leftMargin: 4
			anchors.top: parent.top
			anchors.bottom: parent.bottom

			width: 1
			color: Config.dim
		}

		Item {
			anchors.left: sections.right
			anchors.leftMargin: 10
			anchors.right: parent.right
			anchors.top: parent.top
			anchors.bottom: parent.bottom

			// The work that is going on.
			ListView {
				id: workList

				anchors.fill: parent
				anchors.rightMargin: 8
				clip: true
				spacing: 2
				model: OpenCode.working
				visible: sections.currentIndex === 0

				delegate: Item {
					id: workRow

					required property var modelData
					required property int index

					width: workList.width
					height: root.rowHeight

					// The figure that says what the session is doing: a
					// braille spinner while it works, a question mark when it
					// asks something, and a cross when it failed.
					Text {
						id: figure

						x: 0
						y: 0
						width: 12
						height: root.rowHeight
						verticalAlignment: Text.AlignVCenter
						horizontalAlignment: Text.AlignHCenter

						font.family: Config.fontFamily
						font.pixelSize: Settings.fontSize
						color: modelData.failed || modelData.question ? Config.red : Config.foreground
						text: modelData.question
							? Config.agentIconQuestion
							: (modelData.failed ? Config.agentIconClose : root.braille[(root.spinFrame + workRow.index) % 10])
					}

					// The mark of the provider that is doing the work.
					Image {
						id: mark

						x: figure.width + 4
						y: 1
						width: 15
						height: 15
						visible: modelData.icon !== ""

						source: modelData.icon !== ""
							? "file://" + Quickshell.shellDir + "/assets/providers/" + modelData.icon + ".svg"
							: ""
						sourceSize.width: Math.round(15 * root.dpr)
						sourceSize.height: Math.round(15 * root.dpr)
						fillMode: Image.PreserveAspectFit
					}

					Text {
						anchors.left: mark.visible ? mark.right : figure.right
						anchors.leftMargin: mark.visible ? 6 : 8
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter

						elide: Text.ElideRight

						font.family: Config.fontFamily
						font.pixelSize: Settings.fontSize
						color: modelData.failed || modelData.question ? Config.red : Config.foreground
						text: modelData.title
					}
				}
			}

			// The work that is done.
			ListView {
				id: doneList

				anchors.fill: parent
				anchors.rightMargin: 8
				clip: true
				spacing: 2
				model: OpenCode.doneSessions
				visible: sections.currentIndex === 1

				delegate: Item {
					required property var modelData

					width: doneList.width
					height: root.rowHeight

					// The figure that says the work is over.
					Text {
						id: doneFigure

						x: 0
						y: 0
						width: 12
						height: root.rowHeight
						verticalAlignment: Text.AlignVCenter
						horizontalAlignment: Text.AlignHCenter

						font.family: Config.fontFamily
						font.pixelSize: Settings.fontSize
						color: Config.muted
						text: Config.agentIconDone
					}

					Text {
						anchors.left: doneFigure.right
						anchors.leftMargin: 8
						anchors.right: dismiss.left
						anchors.rightMargin: 6
						anchors.verticalCenter: parent.verticalCenter

						elide: Text.ElideRight

						font.family: Config.fontFamily
						font.pixelSize: Settings.fontSize
						color: Config.muted
						text: modelData.title
					}

					// The cross that takes the finished work off the list.
					Text {
						id: dismiss

						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						width: 14

						horizontalAlignment: Text.AlignHCenter

						font.family: Config.fontFamily
						font.pixelSize: Settings.fontSize
						color: dismissHit.containsMouse ? Config.foreground : Config.muted
						text: Config.iconClose

						MouseArea {
							id: dismissHit

							anchors.fill: parent
							anchors.margins: -4

							onClicked: OpenCode.dismiss(modelData.id)
						}
					}
				}
			}

			// The thumb of the list, which only shows when there is more work
			// than fits.
			Scrollbar {
				view: sections.currentIndex === 1 ? doneList : workList
				offset: 4
			}
		}
	}
}
