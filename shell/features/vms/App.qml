import QtQuick
import QtQuick.Effects
import Quickshell
import qs
import qs.services
import qs.ui
import Yudae.Native

AppWindow {
	id: win

	readonly property var vms: Yudae.vms.list || []
	readonly property string root: Quickshell.env("YUDAE_VM_ROOT") || "/home/gabriel/dotfiles/vm/runs"
	readonly property color ink: Config.foreground
	readonly property color secondary: "#b4b4b4"
	readonly property color faint: "#949494"
	readonly property color rule: "#1f1f1f"
	readonly property color active: "#181818"
	readonly property color hover: "#141414"

	property string selectedName: ""
	property string live: Quickshell.env("YUDAE_VM") || ""
	property bool powerOpen: false
	property string powerConfirm: ""
	readonly property bool focusMode: win.fullscreen && win.live.length > 0
	readonly property string selected: win.live.length > 0 ? win.live : (win.selectedName.length > 0 ? win.selectedName : (Yudae.vms.selected || (win.vms.length > 0 ? win.vms[0].name : "")))
	readonly property var current: {
		for (let i = 0; i < win.vms.length; i++)
			if (win.vms[i].name === win.selected) return win.vms[i];
		return ({});
	}
	readonly property string tier: win.current.tier || "off"
	readonly property bool running: win.tier !== "off"
	readonly property bool awake: win.tier === "hot"

	appTitle: "Virtual machines"
	implicitWidth: 1400
	implicitHeight: 820

	Timer {
		id: confirmTimer
		interval: 5000
		onTriggered: win.powerConfirm = ""
	}

	function act(method, args) {
		Yudae.vmsCommand(method, args);
	}

	function selectVm(name) {
		win.selectedName = name;
		Yudae.vmsCommand("select", { name: name });
	}

	function takeVm(name) {
		win.selectVm(name);
		win.live = name;
		Yudae.vmsCommand("view", { name: name });
	}

	function releaseVm(name) {
		win.act("release", { name: name });
		if (win.live === name) win.live = "";
	}

	function power(action) {
		if (action === "destroy" && win.powerConfirm !== "destroy") {
			win.powerConfirm = "destroy";
			confirmTimer.restart();
			return;
		}

		win.powerOpen = false;
		win.powerConfirm = "";
		win.live = "";
		win.act(action, { name: win.selected });
		if (action === "destroy") win.selectedName = "";
	}

	function lastViewed(stamp) {
		if (!stamp || stamp <= 0) return "never";
		if (stamp < 1000) return "saved";
		const seconds = Math.max(0, Math.floor((Date.now() - stamp) / 1000));
		if (seconds < 60) return "just now";
		const minutes = Math.floor(seconds / 60);
		if (minutes < 60) return minutes + "m ago";
		const hours = Math.floor(minutes / 60);
		if (hours < 24) return hours + "h ago";
		return Math.floor(hours / 24) + "d ago";
	}

	function sessionLabel(vm) {
		const harness = vm.harness || "";
		const title = vm.sessionTitle || vm.session || "";
		if (harness.length > 0 && title.length > 0) return harness + " · " + title;
		if (harness.length > 0) return harness + " · no session";
		if (title.length > 0) return title;
		return "no agent";
	}

	onAppClosed: if (win.live.length > 0)
		Quickshell.execDetached([Quickshell.shellDir + "/../scripts/yudae", "vm", "release", win.live])

	MouseArea {
		anchors.fill: parent
		z: 9
		visible: win.powerOpen
		onClicked: win.powerOpen = false
	}

	Item {
		anchors.fill: parent

		Column {
			id: page

			anchors.fill: parent
			anchors.margins: win.focusMode ? 0 : 24
			spacing: win.focusMode ? 0 : 20

			Row {
				id: pageHeader

				width: parent.width
				height: win.focusMode ? 0 : 40
				visible: !win.focusMode

				Column {
					anchors.verticalCenter: parent.verticalCenter
					spacing: 2

					Text {
						font.family: Config.fontFamily
						font.pixelSize: 24
						font.weight: Font.DemiBold
						color: win.ink
						text: "Virtual machines"
					}

					Text {
						font.family: Config.fontFamily
						font.pixelSize: 12
						color: win.faint
						text: win.vms.length + (win.vms.length === 1 ? " machine" : " machines") + " · local"
					}
				}
			}

			Row {
				id: body

				width: parent.width
				height: page.height - (win.focusMode ? 0 : 60)
				spacing: win.focusMode ? 0 : 24

				Item {
					id: listPane

					width: win.focusMode ? 0 : 340
					height: body.height
					visible: !win.focusMode

					Row {
						id: listHeader

						width: parent.width
						height: 28

						Text {
							width: listHeader.width - listCount.width
							height: listHeader.height
							verticalAlignment: Text.AlignVCenter

							font.family: Config.fontFamily
							font.pixelSize: 12
							font.weight: Font.Medium
							color: win.secondary
							text: "Machines"
						}

						Text {
							id: listCount

							height: listHeader.height
							verticalAlignment: Text.AlignVCenter

							font.family: Config.fontFamily
							font.pixelSize: 12
							color: win.faint
							text: win.vms.length
						}
					}

					ListView {
						id: list

						anchors.top: listHeader.bottom
						anchors.bottom: parent.bottom
						width: parent.width - 8
						clip: true
						model: win.vms
						spacing: 0
						reuseItems: true
						cacheBuffer: 600

						delegate: Item {
							required property var modelData

							width: list.width
							height: 92

							Rectangle {
								anchors.fill: parent
								color: win.selected === modelData.name ? win.active : (rowMouse.containsMouse ? win.hover : "transparent")
							}

							Item {
								id: rowThumb

								x: 0
								y: 19
								width: 96
								height: 54
								clip: true

								Image {
									id: rowImage

									anchors.fill: parent

									source: modelData.thumb === true ? win.root + "/" + modelData.name + "/thumb.jpg?v=" + (modelData.thumbAt || 0) : ""
									fillMode: Image.PreserveAspectCrop
									asynchronous: false
									cache: true
									visible: false
								}

								MultiEffect {
									anchors.fill: parent

									source: rowImage
									saturation: -1.0
									brightness: -0.08
								}
							}

							Column {
								anchors.left: rowThumb.right
								anchors.leftMargin: 12
								anchors.verticalCenter: parent.verticalCenter
								width: parent.width - rowThumb.width - 12
								spacing: 5

								Text {
									id: rowName

									width: parent.width
									elide: Text.ElideRight

									font.family: Config.fontFamily
									font.pixelSize: 14
									font.weight: Font.Medium
									color: win.ink
									text: modelData.name
								}

								Rectangle {
									width: Math.min(rowName.implicitWidth, parent.width)
									height: 1
									color: win.ink
									visible: win.selected === modelData.name
								}

								Text {
									width: parent.width
									elide: Text.ElideRight

									font.family: Config.fontFamily
									font.pixelSize: 11
									color: win.secondary
									text: (modelData.tier || "off") + " · " + (modelData.controller || "agent") + " · " + (modelData.harness || "no agent")
								}

								Text {
									width: parent.width
									elide: Text.ElideRight

									font.family: Config.fontFamily
									font.pixelSize: 11
									color: win.faint
									text: Math.round(modelData.cpu || 0) + "% · " + Math.round((modelData.rssKb || 0) / 1024) + "MB"
								}
							}

							MouseArea {
								id: rowMouse

								anchors.fill: parent
								hoverEnabled: true
								onClicked: win.selectVm(modelData.name)
							}

							Rectangle {
								anchors.left: parent.left
								anchors.right: parent.right
								anchors.bottom: parent.bottom

								height: 1
								color: win.rule
							}
						}
					}

					Scrollbar {
						view: list
						offset: 4
					}

					Text {
						anchors.centerIn: parent

						font.family: Config.fontFamily
						font.pixelSize: 13
						color: win.faint
						text: "No machines"
						visible: win.vms.length === 0
					}

					Rectangle {
						anchors.right: parent.right
						anchors.top: parent.top
						anchors.bottom: parent.bottom

						width: 1
						color: win.rule
					}
				}

				Item {
					id: detail

					width: win.focusMode ? body.width : body.width - listPane.width - 24
					height: body.height

					Row {
						id: detailHeader

						anchors.top: parent.top
						width: parent.width
						height: win.focusMode ? 0 : 40
						spacing: 16
						visible: !win.focusMode

						Text {
							width: parent.width - actions.width - 16
							height: detailHeader.height
							verticalAlignment: Text.AlignVCenter
							elide: Text.ElideRight

							font.family: Config.fontFamily
							font.pixelSize: 24
							font.weight: Font.DemiBold
							color: win.ink
							text: win.current.name || ""
						}

						Row {
							id: actions

							width: implicitWidth
							height: detailHeader.height
							spacing: 14

							Rectangle {
								width: controlLabel.implicitWidth + 28
								height: 32
								color: controlMouse.containsMouse ? "#e6e6e6" : win.ink
								visible: win.live.length === 0 && win.current.name !== undefined

								Text {
									id: controlLabel

									anchors.centerIn: parent

									font.family: Config.fontFamily
									font.pixelSize: 13
									font.weight: Font.DemiBold
									color: Config.surface
									text: "Take control"
								}

								MouseArea {
									id: controlMouse

									anchors.fill: parent
									hoverEnabled: true
									onClicked: win.takeVm(win.current.name)
								}
							}

							Rectangle {
								width: releaseLabel.implicitWidth + 28
								height: 32
								color: releaseMouse.containsMouse ? "#e6e6e6" : win.ink
								visible: win.live.length > 0

								Text {
									id: releaseLabel

									anchors.centerIn: parent

									font.family: Config.fontFamily
									font.pixelSize: 13
									font.weight: Font.DemiBold
									color: Config.surface
									text: "Release"
								}

								MouseArea {
									id: releaseMouse

									anchors.fill: parent
									hoverEnabled: true
									onClicked: win.releaseVm(win.live)
								}
							}
						}
					}

					Flickable {
						id: detailScroll

						anchors.top: detailHeader.bottom
						anchors.topMargin: win.focusMode ? 0 : 10
						width: win.focusMode ? detail.width : detail.width - 10
						height: win.focusMode ? detail.height : detail.height - detailHeader.height - footerRow.height - 30
						contentWidth: width
						contentHeight: scrollColumn.height
						clip: true
						boundsBehavior: Flickable.StopAtBounds
						interactive: !win.live

						WheelHandler {
							enabled: win.live.length > 0

							onWheel: wheel => {
								const maxY = Math.max(0, detailScroll.contentHeight - detailScroll.height);
								detailScroll.contentY = Math.max(0, Math.min(maxY, detailScroll.contentY - wheel.angleDelta.y * 0.8));
								wheel.accepted = true;
							}
						}

						Column {
							id: scrollColumn

							width: detailScroll.width
							spacing: 10

							Rectangle {
								id: stage

								width: parent.width
								height: win.focusMode ? detailScroll.height : Math.round(parent.width * 9 / 16)
								color: "#000000"
								border.width: win.focusMode ? 0 : 1
								border.color: win.rule
								clip: true

								Image {
									id: stageThumb

									anchors.fill: parent

									source: win.live.length === 0 && win.current.thumb === true ? win.root + "/" + win.current.name + "/thumb.jpg?v=" + (win.current.thumbAt || 0) : ""
									fillMode: Image.PreserveAspectFit
									asynchronous: false
									cache: true
									visible: false
								}

								MultiEffect {
									anchors.fill: parent

									source: stageThumb
									saturation: -1.0
									brightness: -0.08
									visible: win.live.length === 0
								}

								Loader {
									anchors.fill: parent
									active: win.live.length > 0
									sourceComponent: displayComponent
								}

								Component {
									id: displayComponent

									VmDisplay {
										anchors.fill: parent
										qmp: win.root + "/" + win.live + "/display.qmp"
										onErrorChanged: if (error.length > 0) console.warn("VmDisplay:", error)
									}
								}
							}

							Row {
								id: readout

								width: parent.width
								height: win.focusMode ? 0 : 56
								visible: !win.focusMode

								Item {
									width: parent.width * 0.5
									height: parent.height

									Column {
										anchors.verticalCenter: parent.verticalCenter
										spacing: 3

										Text {
											font.family: Config.fontFamily
											font.pixelSize: 11
											color: win.faint
											text: "Session"
										}

										Text {
											width: parent.parent.width - 12
											elide: Text.ElideRight

											font.family: Config.fontFamily
											font.pixelSize: 13
											color: win.ink
											text: win.sessionLabel(win.current)
										}
									}
								}

								Item {
									width: parent.width * 0.25
									height: parent.height

									Rectangle {
										anchors.left: parent.left
										anchors.top: parent.top
										anchors.bottom: parent.bottom

										width: 1
										color: win.rule
									}

									Column {
										anchors.left: parent.left
										anchors.leftMargin: 20
										anchors.verticalCenter: parent.verticalCenter
										spacing: 3

										Text {
											font.family: Config.fontFamily
											font.pixelSize: 11
											color: win.faint
											text: "Machine"
										}

										Text {
											width: parent.parent.width - 28
											elide: Text.ElideRight

											font.family: Config.fontFamily
											font.pixelSize: 13
											color: win.ink
											text: win.tier + " · " + (win.current.controller || "agent")
										}
									}
								}

								Item {
									width: parent.width * 0.25
									height: parent.height

									Rectangle {
										anchors.left: parent.left
										anchors.top: parent.top
										anchors.bottom: parent.bottom

										width: 1
										color: win.rule
									}

									Column {
										anchors.left: parent.left
										anchors.leftMargin: 20
										anchors.verticalCenter: parent.verticalCenter
										spacing: 3

										Text {
											font.family: Config.fontFamily
											font.pixelSize: 11
											color: win.faint
											text: "Viewed"
										}

										Text {
											width: parent.parent.width - 28
											elide: Text.ElideRight

											font.family: Config.fontFamily
											font.pixelSize: 13
											color: win.ink
											text: win.lastViewed(win.current.thumbAt || 0)
										}
									}
								}
							}
						}
					}

					Scrollbar {
						view: detailScroll
						offset: 4
					}

					Item {
						id: footerRow

						anchors.left: parent.left
						anchors.right: parent.right
						anchors.bottom: parent.bottom
						height: win.focusMode ? 0 : 26
						visible: !win.focusMode
						z: 10

						Text {
							anchors.left: parent.left
							anchors.verticalCenter: parent.verticalCenter

							font.family: Config.fontFamily
							font.pixelSize: 11
							color: win.powerConfirm === "destroy" ? Config.red : win.faint
							text: win.powerConfirm === "destroy"
								? "destroy deletes the disk"
								: ((win.current.cores || 0) + " cores · " + (win.current.memMb || 0) + " MB")
						}

						Item {
							id: powerButton

							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							width: powerText.implicitWidth + 24
							height: 26

							Rectangle {
								anchors.fill: parent
								color: powerMouse.containsMouse || win.powerOpen ? Config.launcherSearchBox : "transparent"
							}

							Text {
								id: powerText

								anchors.centerIn: parent

								font.family: Config.fontFamily
								font.pixelSize: 12
								color: win.powerOpen ? win.ink : win.secondary
								text: "Power"
							}

							MouseArea {
								id: powerMouse

								anchors.fill: parent
								hoverEnabled: true
								onClicked: {
									win.powerOpen = !win.powerOpen;
									win.powerConfirm = "";
								}
							}
						}

						Rectangle {
							id: powerMenu

							anchors.right: parent.right
							anchors.bottom: parent.top
							anchors.bottomMargin: 6
							width: 190
							height: powerColumn.height + 12
							color: Config.surface
							border.width: 1
							border.color: win.rule
							visible: win.powerOpen
							z: 10
							clip: true

							Column {
								id: powerColumn

								anchors.left: parent.left
								anchors.right: parent.right
								anchors.top: parent.top
								anchors.topMargin: 6
								spacing: 0

								Item {
									width: parent.width
									height: 32
									visible: win.awake

									Rectangle {
										anchors.fill: parent
										color: sleepMouse.containsMouse ? win.hover : "transparent"
									}

									Text {
										anchors.left: parent.left
										anchors.leftMargin: 12
										anchors.verticalCenter: parent.verticalCenter

										font.family: Config.fontFamily
										font.pixelSize: 12
										color: win.secondary
										text: "Sleep"
									}

									MouseArea {
										id: sleepMouse

										anchors.fill: parent
										hoverEnabled: true
										onClicked: win.power("sleep")
									}
								}

								Item {
									width: parent.width
									height: 32
									visible: !win.awake && win.running

									Rectangle {
										anchors.fill: parent
										color: wakeMouse.containsMouse ? win.hover : "transparent"
									}

									Text {
										anchors.left: parent.left
										anchors.leftMargin: 12
										anchors.verticalCenter: parent.verticalCenter

										font.family: Config.fontFamily
										font.pixelSize: 12
										color: win.secondary
										text: "Wake"
									}

									MouseArea {
										id: wakeMouse

										anchors.fill: parent
										hoverEnabled: true
										onClicked: win.power("wake")
									}
								}

								Item {
									width: parent.width
									height: 32

									Rectangle {
										anchors.fill: parent
										color: stopMouse.containsMouse && win.running ? win.hover : "transparent"
									}

									Text {
										anchors.left: parent.left
										anchors.leftMargin: 12
										anchors.verticalCenter: parent.verticalCenter

										font.family: Config.fontFamily
										font.pixelSize: 12
										color: win.running ? win.secondary : Config.dim
										text: "Stop"
									}

									MouseArea {
										id: stopMouse

										anchors.fill: parent
										hoverEnabled: true
										onClicked: if (win.running) win.power("stop")
									}
								}

								Item {
									width: parent.width
									height: 32

									Rectangle {
										anchors.fill: parent
										color: destroyMouse.containsMouse ? win.hover : "transparent"
									}

									Text {
										anchors.left: parent.left
										anchors.leftMargin: 12
										anchors.verticalCenter: parent.verticalCenter

										font.family: Config.fontFamily
										font.pixelSize: 12
										color: win.powerConfirm === "destroy" ? Config.red : win.secondary
										text: win.powerConfirm === "destroy" ? "Confirm destroy" : "Destroy"
									}

									MouseArea {
										id: destroyMouse

										anchors.fill: parent
										hoverEnabled: true
										onClicked: win.power("destroy")
									}
								}
							}
						}
					}
				}
			}
		}
	}
}
