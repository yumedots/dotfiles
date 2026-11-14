#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOME_DIR=${HOME:-/home/gabriel}

link_one() {
	local src=$1
	local dst=$2

	if [ "$src" = "$dst" ]; then
		return 0
	fi

	if [ -L "$dst" ]; then
		if [ "$(readlink "$dst")" = "$src" ]; then
			return 0
		fi
		rm -f "$dst"
	elif [ -e "$dst" ]; then
		echo "refused $dst: a real file is there"
		return 1
	fi

	mkdir -p "$(dirname "$dst")"
	ln -s "$src" "$dst"
	echo "linked $dst -> $src"
}

task_link() {
	local ok=0 entry

	for entry in "$ROOT"/config/* "$ROOT"/config/.[!.]*; do
		[ -e "$entry" ] || continue
		link_one "$entry" "$HOME_DIR/.config/$(basename "$entry")" || ok=1
	done

	link_one "$ROOT/hypr" "$HOME_DIR/.config/hypr" || ok=1
	link_one "$ROOT/systemd/user/yudaemond.service" "$HOME_DIR/.config/systemd/user/yudaemond.service" || ok=1
	link_one "$ROOT/scripts/yudae" "$HOME_DIR/.local/bin/yudae" || ok=1
	link_one "$ROOT/scripts/xmake" "$HOME_DIR/.local/bin/xmake" || ok=1

	link_one "$ROOT/shell/assets/providers/opencode.svg" "$HOME_DIR/.local/share/icons/hicolor/scalable/apps/opencode.svg" || ok=1
	link_one "$ROOT/shell/assets/providers/claude.svg" "$HOME_DIR/.local/share/icons/hicolor/scalable/apps/claude.svg" || ok=1
	link_one "$ROOT/shell/assets/providers/codex.svg" "$HOME_DIR/.local/share/icons/hicolor/scalable/apps/codex.svg" || ok=1
	link_one "$ROOT/shell/assets/providers/opencode-logo.png" "$HOME_DIR/.local/share/icons/hicolor/256x256/apps/opencode.png" || ok=1

	if [ "$ok" -ne 0 ]; then
		echo "link incomplete" >&2
		exit 1
	fi
}

build_plugins() {
	local state=${XDG_STATE_HOME:-$HOME/.local/state}/yudae/build makefile id
	for makefile in "$ROOT"/plugins/*/Makefile; do
		[ -e "$makefile" ] || continue
		id=$(basename "$(dirname "$makefile")")
		case "$id" in _template-*) continue ;; esac
		make -C "$(dirname "$makefile")" OUT="$state/$id" >/dev/null
		echo "built $id"
	done
}

task_build() {
	"$ROOT/scripts/yubuild"
	build_plugins
}

task_plugin() {
	build_plugins
}

task_lint() {
	mkdir -p /tmp/qmlimport
	ln -sfn "$ROOT/shell" /tmp/qmlimport/qs

	local fail=0 file
	while IFS= read -r file; do
		/usr/lib/qt6/bin/qmllint -I /tmp/qmlimport "$file" >/dev/null 2>&1 || {
			echo "qmllint failed: $file" >&2
			/usr/lib/qt6/bin/qmllint -I /tmp/qmlimport "$file" >&2 || true
			fail=1
		}
	done < <(find "$ROOT/shell" -name '*.qml' -not -path '*/cache/*')

	for check in "$ROOT"/shell/ui/*.check.js; do
		[ -e "$check" ] || continue
		node "$check" || fail=1
	done

	python3 "$ROOT/scripts/color-check" || fail=1

	if [ "$fail" -ne 0 ]; then
		exit 1
	fi

	echo "lint clean"
}

task_bench() {
	"$ROOT/scripts/bench" "$@"
}

task_vm() {
	if [ $# -eq 0 ]; then
		echo "usage: xmake vm fetch|packages|golden|ensure|overlay|snapshot|restore|list|bench [tag] (running VMs: yudae vm)" >&2
		exit 2
	fi

	if [ "$1" = bench ]; then
		shift
		exec "$ROOT/vm/bench-images" "$@"
	fi

	exec "$ROOT/vm/images" "$@"
}

task_doctor() {
	local missing=0 check

	for check in zig xmake node make qemu-system-x86_64 qemu-img; do
		if command -v "$check" >/dev/null 2>&1; then
			echo "ok   $check $(command -v "$check")"
		else
			echo "miss $check"
			missing=1
		fi
	done

	for path in /usr/lib/virtiofsd /dev/kvm /dev/vhost-vsock /dev/dri/renderD128; do
		if [ -e "$path" ]; then
			echo "ok   $path"
		else
			echo "miss $path"
			missing=1
		fi
	done

	if [ -x "$ROOT/daemon/zig-out/bin/yudaemond" ]; then
		echo "ok   daemon $ROOT/daemon/zig-out/bin/yudaemond"
	else
		echo "miss daemon binary"
		missing=1
	fi

	if systemctl --user is-enabled yudaemond >/dev/null 2>&1; then
		echo "ok   yudaemond.service"
	else
		echo "miss yudaemond.service"
		missing=1
	fi

	return "$missing"
}

usage() {
	echo "usage: xmake build|plugin|link|lint|bench|vm|doctor" >&2
	exit 2
}

command=${1:-}
shift || true

case "$command" in
	build) task_build ;;
	plugin) task_plugin ;;
	link) task_link ;;
	lint) task_lint ;;
	bench) task_bench "$@" ;;
	vm) task_vm "$@" ;;
	doctor) task_doctor ;;
	*) usage ;;
esac
