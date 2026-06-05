# Bash completion for ccs.

_ccs_bash_completion() {
  local cur cword
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  cword="$COMP_CWORD"

  if [[ "$cword" -eq 1 ]]; then
    # First argument: app type keywords + top-level commands + claude provider names
    local -a app_types
    app_types=("claude" "codex" "codex-sync-sessions")
    local name name_lc cur_lc escaped

    # Add app type keywords
    cur_lc="$(printf '%s' "$cur" | tr '[:upper:]' '[:lower:]')"
    for t in "${app_types[@]}"; do
      local t_lc
      t_lc="$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')"
      if [[ "$t_lc" == "$cur_lc"* ]]; then
        COMPREPLY+=("$t")
      fi
    done

    # Add claude provider names
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

  if [[ "$cword" -eq 2 ]]; then
    # Second argument: check if first arg is an app type → complete providers for that app
    local prev="${COMP_WORDS[1]}"
    case "$prev" in
      codex-sync-sessions)
        # Complete with state-DB provider values + --dry-run flag
        local opt
        for opt in $(ccs --completion-rows --app codex-sync-sessions 2>/dev/null) --dry-run; do
          if [[ "$opt" == "$cur"* ]]; then
            COMPREPLY+=("$opt")
          fi
        done
        return 0
        ;;
      claude)
        local name name_lc cur_lc escaped
        cur_lc="$(printf '%s' "$cur" | tr '[:upper:]' '[:lower:]')"
        while IFS= read -r name; do
          [[ -n "$name" ]] || continue
          name_lc="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
          if [[ "$name_lc" == "$cur_lc"* ]]; then
            printf -v escaped '%q' "$name"
            COMPREPLY+=("$escaped")
          fi
        done < <(ccs --completion-rows --app claude 2>/dev/null | cut -f1)
        return 0
        ;;
      codex)
        local name name_lc cur_lc escaped
        cur_lc="$(printf '%s' "$cur" | tr '[:upper:]' '[:lower:]')"
        while IFS= read -r name; do
          [[ -n "$name" ]] || continue
          name_lc="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
          if [[ "$name_lc" == "$cur_lc"* ]]; then
            printf -v escaped '%q' "$name"
            COMPREPLY+=("$escaped")
          fi
        done < <(ccs --completion-rows --app codex 2>/dev/null | cut -f1)
        return 0
        ;;
    esac
  fi

  return 0
}

complete -F _ccs_bash_completion ccs