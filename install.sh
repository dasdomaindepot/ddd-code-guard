#!/usr/bin/env bash
#
# install.sh — verlinkt ddd-code-guard in dieses Benutzerkonto.
#
# Es wird nichts kopiert, sondern symbolisch verlinkt: ein `git pull` genuegt,
# und jeder Rechner hat denselben Stand. Eine Kopie friert ein und tut dann so,
# als sei sie aktuell.
#
# Was verlinkt wird, ergibt sich aus dem Verzeichnisbaum, nicht aus einer Liste
# im Script.
#
#   claude/skills/<name>/    ->  ~/.claude/skills/<name>
#   claude/agents/<name>.md  ->  ~/.claude/agents/<name>.md
#   claude/commands/<name>.md->  ~/.claude/commands/<name>.md
#   opencode/agent/<name>.md ->  ~/.config/opencode/agent/<name>.md
#
# Exit-Codes:
#   0  alles verlinkt (oder war es schon)
#   1  mindestens ein Ziel blockiert und uebersprungen
#   2  Nutzungsfehler

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
FORCE=0
STAMP="$(date +%Y%m%d-%H%M%S)"
# Sicherungen liegen bewusst ausserhalb von ~/.claude und ~/.config/opencode.
BACKUP_DIR="$HOME/.claude-config-backups/$STAMP"

usage() {
    cat <<'USAGE'
install.sh — ddd-code-guard verlinken

Verwendung: ./install.sh [OPTIONEN]

  --dry-run   nur zeigen, was passieren wuerde
  --force     fremde Symlinks ohne Rueckfrage ersetzen
  -h, --help  diese Hilfe

Echte Dateien am Zielort werden nie geloescht, sondern nach
~/.claude-config-backups/<zeitstempel>/ verschoben.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --force)   FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
else
    C_RESET=""; C_DIM=""; C_GREEN=""; C_RED=""; C_YELLOW=""
fi

n_linked=0; n_kept=0; n_backed=0; n_blocked=0

# Verlinkt eine Quelle auf ein Ziel. Vier Faelle, in dieser Reihenfolge:
# schon richtig verlinkt, fremder Symlink, echte Datei, nichts da.
link_one() {
    local src="$1" dest="$2"
    local dest_dir; dest_dir="$(dirname "$dest")"

    if [ -L "$dest" ]; then
        local current; current="$(readlink -f "$dest" 2>/dev/null || true)"
        if [ "$current" = "$src" ]; then
            printf '  %sok%s        %s\n' "$C_DIM" "$C_RESET" "$dest"
            n_kept=$((n_kept + 1))
            return 0
        fi
        if [ "$FORCE" -eq 0 ]; then
            printf '  %sfremd%s     %s %s(zeigt auf %s -- mit --force ersetzen)%s\n' \
                "$C_RED" "$C_RESET" "$dest" "$C_DIM" "${current:-?}" "$C_RESET"
            n_blocked=$((n_blocked + 1))
            return 1
        fi
        [ "$DRY_RUN" -eq 1 ] || rm -f "$dest"
    elif [ -e "$dest" ]; then
        # Echte Datei oder echtes Verzeichnis: niemals loeschen, nur beiseite legen.
        #
        # Und zwar ausserhalb des Suchpfads. Eine Sicherung als
        # ~/.claude/skills/code-quality.bak-... behielte ihre SKILL.md und
        # wuerde als zweiter, konkurrierender Skill eingelesen — ein Duplikat,
        # das niemand mehr pflegt und das je nach Ladereihenfolge gewinnt.
        # Pfad relativ zu $HOME beibehalten: sonst kollidieren die beiden
        # gleichnamigen code-quality.md aus ~/.claude/agents und
        # ~/.config/opencode/agent im selben Sicherungsordner.
        local backup="$BACKUP_DIR/${dest#$HOME/}"
        printf '  %ssichere%s   %s -> %s\n' "$C_YELLOW" "$C_RESET" "$dest" "${backup/#$HOME/~}"
        if [ "$DRY_RUN" -eq 0 ]; then
            mkdir -p "$(dirname "$backup")" || { n_blocked=$((n_blocked + 1)); return 1; }
            mv "$dest" "$backup" || { n_blocked=$((n_blocked + 1)); return 1; }
        fi
        n_backed=$((n_backed + 1))
    fi

    if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$dest_dir" || { n_blocked=$((n_blocked + 1)); return 1; }
        ln -s "$src" "$dest" || { n_blocked=$((n_blocked + 1)); return 1; }
    fi
    printf '  %sverlinkt%s  %s\n' "$C_GREEN" "$C_RESET" "$dest"
    n_linked=$((n_linked + 1))
}

# Verlinkt jeden Eintrag eines Quellverzeichnisses in ein Zielverzeichnis.
# `find -mindepth 1 -maxdepth 1` statt Glob: faengt den leeren Ordner mit ab.
link_dir() {
    local src_dir="$1" dest_dir="$2" kind="$3"   # kind: d (Verzeichnis) oder f (Datei)
    [ -d "$src_dir" ] || return 0

    local found=0 entry
    while IFS= read -r entry; do
        found=1
        link_one "$entry" "$dest_dir/$(basename "$entry")"
    done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type "$kind" | sort)

    [ "$found" -eq 1 ] || printf '  %s(nichts in %s)%s\n' "$C_DIM" "${src_dir#$REPO_DIR/}" "$C_RESET"
}

echo "ddd-code-guard aus $REPO_DIR"
[ "$DRY_RUN" -eq 1 ] && echo "${C_YELLOW}Probelauf — es wird nichts geaendert.${C_RESET}"
echo

echo "Skills:"
link_dir "$REPO_DIR/claude/skills"   "$HOME/.claude/skills"         d
echo "Agenten (Claude Code):"
link_dir "$REPO_DIR/claude/agents"   "$HOME/.claude/agents"         f
echo "Slash-Kommandos:"
link_dir "$REPO_DIR/claude/commands" "$HOME/.claude/commands"       f
echo "Agenten (opencode):"
link_dir "$REPO_DIR/opencode/agent"  "$HOME/.config/opencode/agent" f

echo
printf '%d verlinkt, %d unveraendert, %d gesichert' "$n_linked" "$n_kept" "$n_backed"
if [ "$n_blocked" -gt 0 ]; then
    printf ', %s%d blockiert%s\n' "$C_RED" "$n_blocked" "$C_RESET"
    exit 1
fi
printf '.\n'
