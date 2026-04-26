#!/usr/bin/env bash
# resolve_self <path>: portable BASH_SOURCE resolver. Handles absolute and
# relative symlink targets without relying on `readlink -f` (BSD/macOS lack
# it). Uses cd + pwd -P for canonicalization. Returns non-zero on error.

resolve_self() {
    local input="${1:-}"
    if [ -z "$input" ]; then
        return 1
    fi
    local current="$input"
    local target
    local current_dir
    local i=0
    # Resolve up to 16 symlink levels (POSIX SYMLOOP_MAX is 8; doubled here).
    while [ -L "$current" ] && [ "$i" -lt 16 ]; do
        target=$(readlink -- "$current")
        case "$target" in
            /*) current="$target" ;;
            *)
                current_dir=$(dirname -- "$current")
                current="$current_dir/$target"
                ;;
        esac
        i=$((i + 1))
    done
    # Hop limit reached but still a symlink — likely a cycle. Fail loudly.
    if [ -L "$current" ]; then
        return 1
    fi
    local final_dir final_base
    final_dir=$(dirname -- "$current")
    final_base=$(basename -- "$current")
    final_dir=$(CDPATH='' cd -- "$final_dir" 2>/dev/null && pwd -P) || return 1
    if [ "$final_dir" = "/" ]; then
        echo "/$final_base"
    else
        echo "$final_dir/$final_base"
    fi
}
