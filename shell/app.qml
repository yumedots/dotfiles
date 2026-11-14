//@ pragma Env QML_IMPORT_PATH=/home/gabriel/dotfiles/shell/native/qml
//@ pragma Env QSG_RHI_BACKEND=opengl
//@ pragma AppId com.yudae.app
import QtQuick
import Quickshell

ShellRoot {
	Loader {
		source: {
			const name = Quickshell.env("YUDAE_APP") || "";
			return name.length > 0 ? "features/" + name + "/App.qml" : "";
		}
	}
}
