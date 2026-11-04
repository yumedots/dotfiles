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
	property string selected: Quickshell.env("YUDAE_VM") || (win.vms.length > 0 ? win.vms[0].name : "")
	readonly property var current: {
		for (let i = 0; i < win.vms.length; i++)
			if (win.vms[i].name === win.selected) return win.vms[i];
		return ({});
	}

	appTitle: "Virtual machines"
	width: 1600
	height: 1000

	function act(method, args) {
		Yudae.vmsCommand(method, args);
	}

	Row {
		anchors.fill: parent
		spacing: 0

		Item {
			id: sidebar

			width: win.fullscreen ? 0 : 360
			height: parent.height
			visible: width > 0
			clip: true

			Column {
				anchors.fill: parent
				anchors.margins: 16
				spacing: 14

				Text {
					width: parent.width

					font.family: Config.fontFamily
					font.pixelSize: Settings.fontSize
					color: Config.muted
					text: win.vms.length + " machines"
				}

				Repeater {
					model: win.vms

					Item {
						required property var modelData

						width: sidebar.width - 32
						height: row.height

						Column {
							id: row

							width: parent.width
							spacing: 3

							Text {
								width: parent.width
								elide: Text.ElideRight

								font.family: Config.fontFamily
								font.pixelSize: Settings.fontSize
								font.weight: win.selected === modelData.name ? Font.Bold : Font.Normal
								color: win.selected === modelData.name ? Config.foreground : Config.muted
								text: modelData.name + "  " + modelData.tier + "  " + modelData.controller
							}

							Text {
								width: parent.width
								elide: Text.ElideRight

								font.family: Config.fontFamily
								font.pixelSize: Settings.fontSize - 1
								color: Config.muted
								text: (modelData.harness || "agent") + "  " + (modelData.sessionTitle || modelData.session || "no session")
							}

							Text {
								width: parent.width
								elide: Text.ElideRight

								font.family: Config.fontFamily
								font.pixelSize: Settings.fontSize - 1
								color: Config.muted
								text: Math.max(0, Math.floor((Date.now() - (modelData.agentSinceMs || Date.now())) / 60000)) + "m  " +
									Math.round(modelData.cpu || 0) + "%  " + Math.round((modelData.rssKb || 0) / 1024) + "MB"
							}

							Row {
								spacing: 12

								Text {
									font.family: Config.fontFamily
									font.pixelSize: Settings.fontSize - 1
									color: Config.foreground
									text: "take control"
									visible: modelData.controller !== "human"

									MouseArea {
										anchors.fill: parent
										onClicked: {
											win.selected = modelData.name;
											win.act("view", { name: modelData.name });
										}
									}
								}

								Text {
									font.family: Config.fontFamily
									font.pixelSize: Settings.fontSize - 1
									color: Config.foreground
									text: "release"
									visible: modelData.controller === "human"

									MouseArea {
										anchors.fill: parent
										onClicked: win.act("release", { name: modelData.name })
									}
								}

								Text {
									font.family: Config.fontFamily
									font.pixelSize: Settings.fontSize - 1
									color: Config.muted
									text: "stop"

									MouseArea {
										anchors.fill: parent
										onClicked: win.act("stop", { name: modelData.name })
									}
								}

								Text {
									font.family: Config.fontFamily
									font.pixelSize: Settings.fontSize - 1
									color: Config.muted
									text: "destroy"

									MouseArea {
										anchors.fill: parent
										onClicked: win.act("destroy", { name: modelData.name })
									}
								}
							}
						}

						MouseArea {
							anchors.fill: parent
							z: -1
							onClicked: win.selected = modelData.name
						}
					}
				}

				Item { width: 1; height: parent.height }

				Item {
					width: 1
					height: 1
				}
			}
		}

		Item {
			width: win.width - sidebar.width
			height: parent.height

			VmDisplay {
				anchors.fill: parent
				qmp: win.selected.length > 0 ? win.root + "/" + win.selected + "/display.qmp" : ""
			}
		}
	}
}
