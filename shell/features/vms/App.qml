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
	property string live: Quickshell.env("YUDAE_VM") || ""
	readonly property string selected: win.live.length > 0 ? win.live : (Yudae.vms.selected || "")
	readonly property var current: {
		for (let i = 0; i < win.vms.length; i++)
			if (win.vms[i].name === win.selected) return win.vms[i];
		return ({});
	}

	appTitle: "Virtual machines"
	implicitWidth: 1400
	implicitHeight: 820

	function act(method, args) {
		Yudae.vmsCommand(method, args);
	}

	onAppClosed: if (win.live.length > 0)
		Quickshell.execDetached([Quickshell.shellDir + "/../scripts/yudae", "vm", "release", win.live])

	function pick(name) {
		win.live = name;
		Yudae.vmsCommand("select", { name: name });
		Yudae.vmsCommand("view", { name: name });
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
								text: modelData.name + "  " + modelData.tier + "  " + (win.live === modelData.name ? "human" : modelData.controller)
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
									visible: win.live !== modelData.name && modelData.controller !== "human"

									MouseArea {
										anchors.fill: parent
										onClicked: win.pick(modelData.name)
									}
								}

								Text {
									font.family: Config.fontFamily
									font.pixelSize: Settings.fontSize - 1
									color: Config.foreground
									text: "release"
									visible: win.live === modelData.name || modelData.controller === "human"

									MouseArea {
										anchors.fill: parent
										onClicked: {
											win.act("release", { name: modelData.name });
											if (win.live === modelData.name) win.live = "";
										}
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
							onClicked: win.pick(modelData.name)
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
			width: parent.width - sidebar.width
			height: parent.height

			Rectangle {
				anchors.fill: parent
				color: "black"
			}

			Flow {
				id: gallery

				anchors.fill: parent
				anchors.margins: 24
				spacing: 16
				visible: win.live.length === 0

				Repeater {
					model: win.vms

					Item {
						required property var modelData

						width: (gallery.width - gallery.spacing) / 2
						height: width * 0.62

						Rectangle {
							anchors.fill: parent

							color: "#101010"
							border.width: 1
							border.color: "#2f2f2f"
							clip: true

							Image {
								id: thumb

								anchors.fill: parent

								source: win.root + "/" + modelData.name + "/thumb.jpg?v=" + (modelData.thumbAt || 0)
								fillMode: Image.PreserveAspectCrop
								asynchronous: true
								cache: false
								visible: false
							}

							MultiEffect {
								anchors.fill: parent

								source: thumb
								saturation: -1.0
								brightness: -0.12
								visible: modelData.thumb === true && thumb.status === Image.Ready
							}

							Rectangle {
								anchors.fill: parent
								color: "#30000000"
								visible: modelData.thumb === true && thumb.status === Image.Ready
							}

							Text {
								anchors.centerIn: parent

								font.family: Config.fontFamily
								font.pixelSize: Settings.fontSize
								color: Config.muted
								text: "no view yet"
								visible: modelData.thumb !== true || thumb.status !== Image.Ready
							}

							Rectangle {
								anchors.left: parent.left
								anchors.right: parent.right
								anchors.bottom: parent.bottom

								height: 56
								color: "#b3000000"

								Column {
									anchors.fill: parent
									anchors.margins: 10
									spacing: 2

									Text {
										width: parent.width
										elide: Text.ElideRight

										font.family: Config.fontFamily
										font.pixelSize: Settings.fontSize
										color: Config.foreground
										text: modelData.name + "  " + modelData.tier + "  " + (win.live === modelData.name ? "human" : modelData.controller)
									}

									Text {
										width: parent.width
										elide: Text.ElideRight

										font.family: Config.fontFamily
										font.pixelSize: Settings.fontSize - 1
										color: Config.muted
										text: (modelData.harness || "agent") + "  " + (modelData.sessionTitle || modelData.session || "no session")
									}
								}
							}
						}

						MouseArea {
							anchors.fill: parent
							onClicked: win.pick(modelData.name)
						}
					}
				}
			}

			Text {
				anchors.centerIn: parent

				font.family: Config.fontFamily
				font.pixelSize: Settings.fontSize
				color: Config.muted
				text: "no virtual machines"
				visible: win.live.length === 0 && win.vms.length === 0
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
