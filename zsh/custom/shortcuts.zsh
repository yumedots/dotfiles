_tab_or_suggest() {
	if (( $#POSTDISPLAY )); then
		zle autosuggest-accept
	elif (( ${+widgets[fzf-completion]} )); then
		zle fzf-completion
	else
		zle expand-or-complete
	fi
}

zle -N _tab_or_suggest
bindkey '^I' _tab_or_suggest

f() {
	local cmd
	cmd=$(fc -l 1 | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+//' | awk '!seen[$0]++' | fzf --no-sort --tac) || return
	print -z -- "$cmd"
}

ff() {
	local file
	file=$(fzf) || return
	print -z -- "$file"
}

fcd() {
	local dir
	dir=$(fd --type d --hidden --no-ignore --exclude .git --exclude node_modules | fzf --no-preview --scheme=path) || return
	builtin cd -- "$dir"
}
