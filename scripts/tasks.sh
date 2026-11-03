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

usage() {
	echo "usage: xmake link|lint|bench|hypr|vm|doctor" >&2
	exit 2
}

case "${1:-}" in
	link) task_link ;;
	*) usage ;;
esac
