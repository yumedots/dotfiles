import QtQuick
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
	readonly property color sidebar: "#0a0a0a"
	readonly property string vmGlyph: "\uDB80\uDF79"
	readonly property color active: "#181818"
	readonly property color hover: "#141414"

	property string selectedName: ""
	property string live: Quickshell.env("YUDAE_VM") || ""
	property bool powerOpen: false
	property bool settingsOpen: false
	property Item menuAnchor: null
	property string menuVm: ""
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
	readonly property var powerEntries: {
		const list = [];
		if (win.awake) list.push({ label: "Sleep", action: "sleep" });
		else if (win.running) list.push({ label: "Wake", action: "wake" });
		list.push({ label: "Stop", action: "stop", enabled: win.running });
		list.push({ label: win.powerConfirm === "destroy" ? "Confirm destroy" : "Destroy", action: "destroy", danger: true });
		return list;
	}

	appTitle: "Virtual Machine Manager"
	appMinWidth: 960
	appMinHeight: 560
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

	function closeMenus() {
		win.powerOpen = false;
		win.settingsOpen = false;
		win.powerConfirm = "";
		win.menuVm = "";
	}

	function openMenu(name, anchor) {
		const same = win.menuVm === name && win.powerOpen;
		win.closeMenus();
		if (same)
			return;

		win.selectVm(name);
		win.menuAnchor = anchor;
		win.menuVm = name;
		win.powerOpen = true;
	}

	function openSettings(name) {
		win.closeMenus();
		win.selectVm(name);
		win.menuVm = name;
		win.settingsOpen = true;
	}

	function power(action) {
		if (action === "destroy" && win.powerConfirm !== "destroy") {
			win.powerConfirm = "destroy";
			confirmTimer.restart();
			return;
		}

		win.closeMenus();
		win.live = "";
		win.act(action, { name: win.selected });
		if (action === "destroy") win.selectedName = "";
	}

	function settingsRows() {
		return [
			{ label: "Cores", value: win.current.cores || 1, min: 1, max: 32, step: 1, suffix: "" },
			{ label: "Memory", value: win.current.memMb || 512, min: 512, max: 65536, step: 512, suffix: "MB" }
		];
	}

	function configure(index, value) {
		if (win.selected.length === 0)
			return;

		if (index === 0) win.act("config", { name: win.selected, cores: value });
		else win.act("config", { name: win.selected, mem: value });
	}

	function sessionLabel(vm) {
		const title = vm.sessionTitle || vm.session || "";
		if (title.length > 0) return title;
		return (vm.harness || "").length > 0 ? "no session" : "no agent";
	}

	component AgentLine: Row {
		id: line

		property var vm: ({})
		property int size: 13
		property real maxWidth: 400
		property color ink: win.secondary

		spacing: 6

		Image {
			anchors.verticalCenter: parent.verticalCenter
			width: line.size + 2
			height: line.size + 2
			visible: (line.vm.harness || "") !== ""
			source: visible ? "file://" + Quickshell.shellDir + "/assets/providers/" + line.vm.harness + ".svg?v=4" : ""
			sourceSize.width: width * 2
			sourceSize.height: height * 2
			fillMode: Image.PreserveAspectFit
		}

		Text {
			width: Math.min(implicitWidth, Math.max(0, line.maxWidth - line.size - 8))
			elide: Text.ElideRight

			font.family: Config.fontFamily
			font.pixelSize: line.size
			color: line.ink
			text: win.sessionLabel(line.vm)
		}
	}

	onAppClosed: if (win.live.length > 0)
		Quickshell.execDetached([Quickshell.shellDir + "/../scripts/yudae", "vm", "release", win.live])

	MouseArea {
		anchors.fill: parent
		z: 9
		visible: win.powerOpen || win.settingsOpen
		onPressed: mouse => {
			const anchor = win.menuAnchor;
			const point = anchor ? mapToItem(anchor, mouse.x, mouse.y) : null;
			const onAnchor = point && point.x >= -6 && point.y >= -6 && point.x <= anchor.width + 6 && point.y <= anchor.height + 6;
			if (!onAnchor)
				win.closeMenus();
			mouse.accepted = false;
		}
	}

	ContextMenu {
		id: powerMenu

		anchor: win.menuAnchor
		entries: win.powerEntries
		z: 11
		visible: win.powerOpen && !win.focusMode
		onPicked: entry => win.power(entry.action)
	}

	Rectangle {
		id: settingsPage

		anchors.fill: parent
		z: 12
		color: Config.surface
		visible: win.settingsOpen && !win.focusMode

		MouseArea {
			anchors.fill: parent
			hoverEnabled: true
		}

		Item {
			id: settingsHeader

			anchors.left: parent.left
			anchors.right: parent.right
			anchors.top: parent.top
			height: 64

			Text {
				id: backIcon

				anchors.left: parent.left
				anchors.leftMargin: 24
				anchors.verticalCenter: parent.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: 18
				color: backMouse.containsMouse ? win.ink : win.secondary
				text: ""

				MouseArea {
					id: backMouse

					anchors.fill: parent
					anchors.margins: -10
					hoverEnabled: true
					onClicked: win.closeMenus()
				}
			}

			Text {
				anchors.left: backIcon.right
				anchors.leftMargin: 20
				anchors.verticalCenter: parent.verticalCenter

				font.family: Config.fontFamily
				font.pixelSize: 20
				font.weight: Font.DemiBold
				color: win.ink
				text: win.current.name || ""
			}

			Rectangle {
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.bottom: parent.bottom
				height: 1
				color: win.rule
			}
		}

		Item {
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.top: settingsHeader.bottom
			anchors.bottom: parent.bottom

			Item {
				id: settingsSide

				anchors.left: parent.left
				anchors.top: parent.top
				anchors.bottom: parent.bottom
				width: 300

				Rectangle {
					anchors.left: parent.left
					anchors.right: parent.right
					anchors.top: parent.top
					anchors.topMargin: 16
					height: 44
					color: win.active

					Text {
						anchors.left: parent.left
						anchors.leftMargin: 24
						anchors.verticalCenter: parent.verticalCenter

						font.family: Config.fontFamily
						font.pixelSize: 14
						color: win.ink
						text: "Hardware"
					}
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
				anchors.left: settingsSide.right
				anchors.right: parent.right
				anchors.top: parent.top
				anchors.bottom: parent.bottom

				Column {
					anchors.horizontalCenter: parent.horizontalCenter
					anchors.top: parent.top
					anchors.topMargin: 32
					width: Math.min(720, parent.width - 64)

					Repeater {
						model: win.settingsRows()

						delegate: Item {
							id: setting

							required property var modelData
							required property int index

							width: parent.width
							height: 64

							Text {
								anchors.left: parent.left
								anchors.verticalCenter: parent.verticalCenter

								font.family: Config.fontFamily
								font.pixelSize: 15
								color: win.ink
								text: setting.modelData.label
							}

							Row {
								anchors.right: parent.right
								anchors.verticalCenter: parent.verticalCenter
								spacing: 8

								Item {
									width: 32
									height: 32

									Text {
										anchors.centerIn: parent
										font.family: Config.fontFamily
										font.pixelSize: 14
										color: minus.containsMouse ? win.ink : win.faint
										text: ""
									}

									MouseArea {
										id: minus

										anchors.fill: parent
										hoverEnabled: true
										onClicked: win.configure(setting.index, Math.max(setting.modelData.min, setting.modelData.value - setting.modelData.step))
									}
								}

								Text {
									width: 110
									height: 32
									horizontalAlignment: Text.AlignHCenter
									verticalAlignment: Text.AlignVCenter

									font.family: Config.fontFamily
									font.pixelSize: 15
									color: win.ink
									text: setting.modelData.value + (setting.modelData.suffix ? " " + setting.modelData.suffix : "")
								}

								Item {
									width: 32
									height: 32

									Text {
										anchors.centerIn: parent
										font.family: Config.fontFamily
										font.pixelSize: 14
										color: plus.containsMouse ? win.ink : win.faint
										text: ""
									}

									MouseArea {
										id: plus

										anchors.fill: parent
										hoverEnabled: true
										onClicked: win.configure(setting.index, Math.min(setting.modelData.max, setting.modelData.value + setting.modelData.step))
									}
								}
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
				}
			}
		}
	}

	Item {
		id: frame

		anchors.fill: parent

		Row {
			id: body

			anchors.fill: parent

			Rectangle {
				id: listPane

				width: win.focusMode ? 0 : Math.max(240, Math.min(300, body.width * 0.28))
				height: body.height
				color: win.sidebar
				visible: !win.focusMode

				ListView {
					id: list

					anchors.fill: parent
					anchors.rightMargin: 1
					clip: true
					model: win.vms
					spacing: 0
					cacheBuffer: 600
					readonly property int hoverIndex: listHover.containsMouse ? list.indexAt(listHover.mouseX, listHover.mouseY + list.contentY) : -1

					delegate: Item {
						id: row

						required property var modelData
						required property int index
						readonly property bool rowHovered: list.hoverIndex === row.index
						readonly property bool actionsShown: row.rowHovered || win.menuVm === modelData.name

						width: list.width
						height: 64

						Rectangle {
							anchors.fill: parent
							color: win.selected === modelData.name ? win.active : (row.rowHovered ? win.hover : "transparent")
						}

						Text {
							id: rowIcon

							anchors.left: parent.left
							anchors.leftMargin: 20
							anchors.verticalCenter: parent.verticalCenter

							font.family: Config.fontFamily
							font.pixelSize: 22
							color: win.selected === row.modelData.name ? win.ink : win.secondary
							text: win.vmGlyph
						}

						Column {
							anchors.left: rowIcon.right
							anchors.leftMargin: 16
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width - 20 - rowIcon.width - 16 - rowActions.width - 8
							spacing: 3

							Text {
								width: parent.width
								elide: Text.ElideRight

								font.family: Config.fontFamily
								font.pixelSize: 14
								font.weight: Font.Medium
								color: win.ink
								text: row.modelData.name
							}

							AgentLine {
								vm: row.modelData
								size: 12
								maxWidth: parent.width
							}
						}

						MouseArea {
							anchors.fill: parent
							onClicked: win.selectVm(row.modelData.name)
						}

						Row {
							id: rowActions

							anchors.right: parent.right
							anchors.rightMargin: 12
							anchors.verticalCenter: parent.verticalCenter
							spacing: 14

							RevealIcon {
								id: gearIcon

								shown: row.actionsShown
								font.pixelSize: 15
								baseColor: win.secondary
								hoverColor: win.ink
								text: "\uf013"
								onClicked: win.openSettings(row.modelData.name)
							}

							RevealIcon {
								id: powerIcon

								shown: row.actionsShown
								font.pixelSize: 15
								baseColor: win.powerOpen && win.menuVm === row.modelData.name ? win.ink : win.secondary
								hoverColor: win.ink
								text: "\uf011"
								onClicked: win.openMenu(row.modelData.name, powerIcon)
							}
						}
					}
				}

				MouseArea {
					id: listHover

					anchors.fill: list
					z: 5
					acceptedButtons: Qt.NoButton
					hoverEnabled: true
				}

				Scrollbar {
					view: list
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

				width: body.width - listPane.width
				height: body.height

				Item {
					id: detailBody

					anchors.fill: parent
					anchors.leftMargin: win.focusMode ? 0 : 24
					anchors.rightMargin: win.focusMode ? 0 : 24
					anchors.bottomMargin: win.focusMode ? 0 : 24

					Row {
						id: detailHeader

						anchors.top: parent.top
						width: parent.width
						height: win.focusMode ? 0 : 64
						spacing: 20
						visible: !win.focusMode

						Text {
							width: parent.width - actions.width - 20
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
							spacing: 20

							Text {
								height: detailHeader.height
								verticalAlignment: Text.AlignVCenter

								font.family: Config.fontFamily
								font.pixelSize: 12
								color: win.powerConfirm === "destroy" ? Config.red : win.faint
								visible: win.current.name !== undefined
								text: win.powerConfirm === "destroy"
									? "destroy deletes the disk"
									: (Config.iconCpu + "  " + (win.current.cores || 0) + " cores  " + (win.current.memMb || 0) + " MB")
							}

							Rectangle {
								anchors.verticalCenter: parent.verticalCenter
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
								anchors.verticalCenter: parent.verticalCenter
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

					Item {
						id: stageArea

						anchors.top: detailHeader.bottom
						anchors.topMargin: win.focusMode ? 0 : 16
						anchors.bottom: parent.bottom
						anchors.left: parent.left
						anchors.right: parent.right

						Rectangle {
							id: stage

							width: win.focusMode ? stageArea.width : Math.min(stageArea.width, Math.round(stageArea.height * 16 / 9))
							height: win.focusMode ? stageArea.height : Math.round(width * 9 / 16)
							color: "#000000"
							clip: true
							visible: win.live.length > 0 || win.running

							Column {
								anchors.centerIn: parent
								spacing: 14
								visible: win.live.length === 0

								Image {
									anchors.horizontalCenter: parent.horizontalCenter
									width: 40
									height: 40
									visible: (win.current.harness || "") !== ""
									source: visible ? "file://" + Quickshell.shellDir + "/assets/providers/" + win.current.harness + ".svg?v=4" : ""
									sourceSize.width: 80
									sourceSize.height: 80
									fillMode: Image.PreserveAspectFit
								}

								Text {
									anchors.horizontalCenter: parent.horizontalCenter

									font.family: Config.fontFamily
									font.pixelSize: 14
									color: win.secondary
									text: "Agents are working here"
								}
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
					}
				}
			}
		}
	}
}
