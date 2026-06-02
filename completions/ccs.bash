# Bash completion for ccs.

_ccs_bash_completion() {
  local cur cword
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  cword="$COMP_CWORD"

  if [[ "$cword" -eq 1 ]]; then
    local name name_lc cur_lc escaped
    cur_lc="$(printf '%s' "$cur" | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      name_lc="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
      if [[ "$name_lc" == "$cur_lc"* ]]; then
        printf -v escaped '%q' "$name"
        COMPREPLY+=("$escaped")
      fi
    done < <(ccs --completion-rows 2>/dev/null | cut -f1)
    return 0
  fi

  if [[ "$cword" -ge 2 ]]; then
    COMPREPLY=( $(compgen -d -- "$cur") )
    return 0
  fi
}

complete -F _ccs_bash_completion ccs
