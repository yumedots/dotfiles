import QtQuick
import Quickshell
import qs
import qs.services
import qs.ui

// The agent panel: the work that is done, the agent itself, and the plan the
// agent runs on, side by side.
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

	// The height of one row of work.
	readonly property real rowHeight: Settings.fontSize + 6

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

	implicitWidth: Config.agentPanelWidth + 2 * Config.agentPanelPadding
	implicitHeight: Config.agentPanelHeight + 2 * Config.agentPanelPadding

	clip: true

	// The clock the countdowns read, so a panel that sits open does not keep
	// showing a reset time that has already gone by.
	property real now: Date.now()

	// The message the agent is asking about, and the one that was put away.
	// A new message comes back on its own.
	property string detail: OpenCode.detailText
	property string dismissedDetail: ""

	readonly property bool detailHidden: root.detail !== "" && root.dismissedDetail === root.detail;

	function dismissDetail() {
		root.dismissedDetail = root.detail;
	}

	Timer {
		interval: 30000
		repeat: true
		running: true
		triggeredOnStart: true

		onTriggered: root.now = Date.now()
	}

	// How long until a window of the allowance resets. One measure at a time:
	// the days when there are days, the hours when there are not.
	function countdown(text) {
		const at = Date.parse(String(text || ""));

		if (!isFinite(at))
			return "";

		const minutes = Math.floor((at - root.now) / 60000);

		if (minutes <= 0)
			return "now";

		const days = Math.floor(minutes / 1440);

		if (days > 0)
			return days + "d";

		const hours = Math.floor(minutes / 60);

		if (hours > 0)
			return hours + "h";

		return minutes + "m";
	}

	Row {
		id: row

		anchors.fill: parent
		anchors.margins: Config.agentPanelPadding

		spacing: 10

		// The work that is done, on the left.
		Item {
			id: doneBox

			width: Config.agentDoneWidth
			height: row.height

			Text {
				id: doneTitle

				anchors.top: parent.top
				anchors.left: parent.left

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.muted
				text: Config.agentDoneTitle
			}

			ListView {
				id: doneList

				anchors.top: doneTitle.bottom
				anchors.topMargin: 4
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.bottom: parent.bottom

				clip: true
				spacing: 2
				model: OpenCode.doneSessions

				delegate: AgentRow {
					required property var modelData

					width: doneList.width - 8
					height: root.rowHeight

					kind: "done"
					title: modelData.title
					dismissable: true

					onDismissed: OpenCode.dismiss(modelData.id)
				}
			}

			// The thumb of the list, which only shows when there is more done
			// work than fits.
			Scrollbar {
				view: doneList
				offset: 4
			}
		}

		// The line that splits the done work from the agent.
		Rectangle {
			width: 1
			height: row.height
			color: Config.dim
		}

		// The agent itself, in the middle.
		Item {
			id: faceBox

			width: Config.agentColumnWidth
			height: row.height

			// The face.
			Item {
				id: face

				anchors.top: parent.top
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

					// The face is only turned while the panel is open, so a
					// face that nobody sees costs nothing.
					live: root.source ? root.source.popupVisible : true

					// The card behind the panel is flat, so the eyes are
					// painted in it and the body can turn on its own.
					paintEyes: true

					bodyColor: Config.foreground
					eyeColor: Config.surface
				}

				// The question mark, when the agent is waiting for the user.
				Text {
					anchors.left: parent.left
					anchors.leftMargin: 4
					anchors.top: parent.top
					anchors.topMargin: 4

					visible: root.state === "blocked"

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize + 4
					color: Config.red
					text: Config.agentIconQuestion
				}
			}

			// The state of the agent, and what it is asking about.
			Column {
				id: stateBox

				anchors.top: face.bottom
				anchors.topMargin: Config.agentPanelPadding
				anchors.horizontalCenter: parent.horizontalCenter

				width: Config.agentColumnWidth
				spacing: 2

				Text {
					width: parent.width
					horizontalAlignment: Text.AlignHCenter

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: Config.foreground
					text: Config.agentPanelTitle
				}

				// The state, with the spinner that turns while the agent is
				// working. It sits in a box of its own, because a column
				// puts its children on the left.
				Item {
					id: stateRow

					width: parent.width
					height: root.rowHeight

					Row {
						id: stateContent

						anchors.horizontalCenter: parent.horizontalCenter
						anchors.verticalCenter: parent.verticalCenter

						spacing: 5

						Braille {
							visible: root.state === "working"
							running: root.state === "working"
							ink: Config.muted
						}

						Text {
							font.family: Config.fontFamily
							font.pixelSize: Settings.fontSize
							color: root.state === "error" ? Config.red : Config.muted
							text: OpenCode.connected ? root.stateText : "OpenCode offline"
						}
					}
				}

				// The detail always holds its place, so the work below it
				// does not jump when a message comes and goes. The cross
				// puts the message away.
				Item {
					width: parent.width
					height: root.rowHeight

					Row {
						anchors.horizontalCenter: parent.horizontalCenter
						anchors.verticalCenter: parent.verticalCenter

						spacing: 6

						Text {
							width: Math.min(implicitWidth, parent.parent.width - 40)
							visible: !root.detailHidden

							elide: Text.ElideRight

							font.family: Config.fontFamily
							font.pixelSize: Settings.fontSize
							color: Config.muted
							text: root.detail
						}

						Text {
							visible: !root.detailHidden

							font.family: Config.fontFamily
							font.pixelSize: Settings.fontSize
							color: dismissDetailHit.containsMouse ? Config.foreground : Config.muted
							text: Config.iconClose

							MouseArea {
								id: dismissDetailHit

								anchors.fill: parent
								anchors.margins: -4

								onClicked: root.dismissDetail()
							}
						}
					}
				}
			}

			// The work that is going on. Every session that is running gets a
			// row, so several of them working at once are all of them visible.
			ListView {
				id: workList

				anchors.top: stateBox.bottom
				anchors.topMargin: Config.agentPanelPadding
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.bottom: parent.bottom

				clip: true
				spacing: 2
				model: OpenCode.working

				delegate: AgentRow {
					required property var modelData

					width: workList.width - 8
					height: root.rowHeight

					kind: modelData.working ? "working" : (modelData.question ? "question" : "failed")
					icon: modelData.icon
					title: modelData.title
				}
			}

			// The thumb of the work list, which only shows when there is more
			// work than fits.
			Scrollbar {
				view: workList
				offset: 4
			}
		}

		// The line that splits the agent from the plan.
		Rectangle {
			width: 1
			height: row.height
			color: Config.dim
		}

		// The plan the agent runs on, and how much of it is left.
		Item {
			id: planBox

			width: Config.agentPlanWidth
			height: row.height

			Text {
				id: planTitle

				anchors.top: parent.top
				anchors.left: parent.left

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.muted
				text: Config.agentPlanTitle
			}

			Flickable {
				id: planFlick

				anchors.top: planTitle.bottom
				anchors.topMargin: 4
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.bottom: parent.bottom

				contentWidth: width
				contentHeight: planStack.height
				clip: true

				Column {
					id: planStack

					width: planFlick.width
					spacing: 6

					// The mark of the plan, with its name.
					Row {
						visible: OpenCode.limits.length > 0
						spacing: 6

						Image {
							width: 18
							height: 18

							source: "file://" + Quickshell.shellDir + "/assets/providers/" + Config.agentPlanIcon + ".svg?v=3"
							sourceSize.width: Math.round(18 * root.dpr)
							sourceSize.height: Math.round(18 * root.dpr)
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

							// The label and the numbers are fixed columns, so
							// every bar starts and ends in the same place. The
							// percentage sits before the bar, so the bar is
							// read as the rest.
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

							StepBar {
								id: limitMeter

								anchors.left: limitLabel.right
								anchors.right: limitValue.left
								anchors.leftMargin: 8
								anchors.rightMargin: 10
								anchors.verticalCenter: parent.verticalCenter

								level: modelData.percent / 100
								ink: limitRow.alarming ? Config.red : Config.foreground
								track: Config.dim
							}

							Text {
								id: limitValue

								anchors.right: limitReset.left
								anchors.rightMargin: 6
								anchors.verticalCenter: parent.verticalCenter
								width: 34

								horizontalAlignment: Text.AlignRight

								font.family: Config.fontFamily
								font.pixelSize: Settings.fontSize
								color: limitRow.alarming ? Config.red : Config.muted
								text: Math.round(modelData.percent) + "%"
							}

							Text {
								id: limitReset

								anchors.right: parent.right
								anchors.verticalCenter: parent.verticalCenter
								width: 26

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
			}

			// The thumb of the plan, which only shows when there is more plan
			// than fits.
			Scrollbar {
				view: planFlick
				offset: -4
			}
		}
	}
}
