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

	if [ "$ok" -ne 0 ]; then
		echo "link incomplete" >&2
		exit 1
	fi
}

task_build() {
	"$ROOT/scripts/yubuild"

	for makefile in "$ROOT"/hypr/plugins/*/Makefile; do
		[ -e "$makefile" ] || continue
		make -C "$(dirname "$makefile")" >/dev/null
	done
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

	if [ "$fail" -ne 0 ]; then
		exit 1
	fi

	echo "lint clean"
}

task_bench() {
	"$ROOT/scripts/bench" "$@"
}

task_hypr() {
	if [ $# -eq 0 ]; then
		"$ROOT/scripts/hypr-test" list
		return
	fi

	"$ROOT/scripts/hypr-test" "$@"
}

task_vm() {
	"$ROOT/scripts/vm" "$@"
}

task_doctor() {
	local missing=0 check

	for check in zig xmake node make qemu-system-x86_64 virtiofsd qemu-img; do
		if command -v "$check" >/dev/null 2>&1; then
			echo "ok   $check $(command -v "$check")"
		else
			echo "miss $check"
			missing=1
		fi
	done

	for path in /dev/kvm /dev/vhost-vsock /dev/dri/renderD128; do
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
	echo "usage: xmake build|link|lint|bench|hypr|vm|doctor" >&2
	exit 2
}

command=${1:-}
shift || true

case "$command" in
	build) task_build ;;
	link) task_link ;;
	lint) task_lint ;;
	bench) task_bench "$@" ;;
	hypr) task_hypr "$@" ;;
	vm) task_vm "$@" ;;
	doctor) task_doctor ;;
	*) usage ;;
esac
