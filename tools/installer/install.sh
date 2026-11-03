#!/usr/bin/env bash
# Installs @SHORT@ @VARIANT@ into a Beyond All Reason install on Linux.
#   ./install.sh                 find BAR, install
#   ./install.sh /path/to/data   the BAR data folder (the one with engine/ inside)
#   ./install.sh -y ...          answer yes to every question
set -euo pipefail

SHORT="@SHORT@"
VARIANT="@VARIANT@"
ENGINE="@ENGINE@"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$HERE/payload/$SHORT/$VARIANT"
YES=0
ARG=""
for a in "$@"; do
    case "$a" in
        -y|--yes) YES=1 ;;
        *) ARG="$a" ;;
    esac
done

say() { echo "  $*"; }
fail() { echo; echo "  INSTALL FAILED: $*" >&2; exit 1; }
ask() {
    [ "$YES" = 1 ] && return 0
    read -r -p "  $1 [y/N] " r
    [[ "$r" =~ ^([yY]|[yY][eE][sS])$ ]]
}

data_dir_of() {
    local d
    for d in "$1" "$1/data"; do
        [ -d "$d/engine" ] && { (cd "$d" && pwd); return 0; }
    done
    return 1
}

find_bar() {
    local r
    for r in \
        "${BAR_DATA:-}" \
        "${XDG_STATE_HOME:-$HOME/.local/state}/Beyond All Reason" \
        "${XDG_DATA_HOME:-$HOME/.local/share}/Beyond All Reason" \
        "$HOME/.var/app/info.beyondallreason.bar/data/Beyond All Reason" \
        "$HOME/.var/app/info.beyondallreason.bar/state/Beyond All Reason" \
        "$HOME/Documents/Beyond All Reason" \
        "$HOME/.steam/steam/steamapps/common/Beyond All Reason" \
        "$HOME/.local/share/Steam/steamapps/common/Beyond All Reason"; do
        [ -n "$r" ] && data_dir_of "$r" && return 0
    done
    return 1
}

bar_running() {
    pgrep -f -i 'spring|Beyond-All-Reason|beyond-all-reason' >/dev/null 2>&1
}

# The lobby hides every AI it has no simple name for while simpleAiList is on (its default), and the
# checkbox sits on the Developer tab, which only devmode.txt shows. The lobby rewrites IGL_data.lua
# when it closes, so this runs with BAR closed.
show_full_ai_list() {
    local data="$1" igl="$1/LuaMenu/Config/IGL_data.lua"
    touch "$data/devmode.txt"
    if [ -f "$igl" ]; then
        grep -Eq 'simpleAiList[[:space:]]*=[[:space:]]*false' "$igl" && return 0
        cp -f "$igl" "$igl.before-apex"
        if grep -Eq 'simpleAiList[[:space:]]*=[[:space:]]*true' "$igl"; then
            sed -i -E 's/simpleAiList[[:space:]]*=[[:space:]]*true/simpleAiList = false/' "$igl"
        elif grep -Eq '\["Chili lobby"\][[:space:]]*=[[:space:]]*\{' "$igl"; then
            sed -i -E '0,/\["Chili lobby"\][[:space:]]*=[[:space:]]*\{/s//&\n\t\tsimpleAiList = false,/' "$igl"
        elif grep -Eq 'return[[:space:]]*\{' "$igl"; then
            sed -i -E '0,/return[[:space:]]*\{/s//&\n\t["Chili lobby"] = {\n\t\tsimpleAiList = false,\n\t},/' "$igl"
        else
            return 1
        fi
    else
        mkdir -p "$(dirname "$igl")"
        printf 'return {\n\t["Chili lobby"] = {\n\t\tsimpleAiList = false,\n\t},\n}\n' > "$igl"
    fi
    grep -Eq 'simpleAiList[[:space:]]*=[[:space:]]*false' "$igl" \
        && ! grep -Eq 'simpleAiList[[:space:]]*=[[:space:]]*true' "$igl"
}

echo
echo "  Installing $SHORT $VARIANT for Beyond All Reason (Linux)"
echo

[ -f "$PAYLOAD/AIInfo.lua" ] || fail "the AI files are missing from $PAYLOAD. Extract the whole zip and run install.sh again."
[ -f "$PAYLOAD/libSkirmishAI.so" ] || fail "this package has no Linux library (libSkirmishAI.so)."

if [ -n "$ARG" ]; then
    DATA="$(data_dir_of "$ARG")" || fail "no BAR data folder at $ARG (expected a folder with engine/ inside)."
else
    DATA="$(find_bar)" || fail "could not find Beyond All Reason. Run again with its data folder: ./install.sh \"/path/to/Beyond All Reason\""
fi
say "BAR found:  $DATA"

ENG_DIR=""
if [ -d "$DATA/engine/$ENGINE/AI/Skirmish" ]; then
    ENG_DIR="$DATA/engine/$ENGINE"
else
    NEWEST="$(ls -1dt "$DATA"/engine/*/ 2>/dev/null | while read -r e; do [ -d "$e/AI/Skirmish" ] && echo "${e%/}" && break; done)"
    [ -n "$NEWEST" ] || fail "BAR has no engine installed yet. Start BAR once, let it update, then run this again."
    echo
    say "This AI was built for engine $ENGINE, which is not installed."
    say "Installed: $(ls -1 "$DATA/engine" | tr '\n' ' ')"
    say "It may fail to load on $(basename "$NEWEST"). A build for that engine is safer."
    ask "Install into $(basename "$NEWEST") anyway?" || fail "cancelled."
    ENG_DIR="$NEWEST"
fi
say "Engine:     $(basename "$ENG_DIR")"

TARGET="$ENG_DIR/AI/Skirmish/$SHORT/$VARIANT"
if [ -e "$TARGET" ]; then
    say "Replacing the copy already installed."
    rm -rf "$TARGET" || fail "could not remove the old copy at $TARGET"
fi
mkdir -p "$(dirname "$TARGET")"
cp -R "$PAYLOAD" "$TARGET" || fail "copying to $TARGET failed."
chmod 755 "$TARGET/libSkirmishAI.so"
[ -f "$TARGET/libSkirmishAI.so" ] || fail "the copy is incomplete at $TARGET."
say "AI files:   $TARGET"

LISTED=0
while true; do
    if ! bar_running; then
        if show_full_ai_list "$DATA"; then LISTED=1; else say "Could not change the lobby setting."; fi
        break
    fi
    echo
    say "BAR is open. Its lobby must be closed to switch on the full AI list"
    say "(it saves its settings when it closes and would undo the change)."
    [ "$YES" = 1 ] && break
    read -r -p "  Close BAR completely, then press Enter (or type S to skip) " r
    [[ "$r" =~ ^[sS] ]] && break
done

echo
echo "  Done. $SHORT $VARIANT is installed."
if [ "$LISTED" = 1 ]; then
    say "The lobby will show the full AI list (devmode.txt made, 'Simple AI list' off)."
else
    say "The lobby setting was NOT changed, so $SHORT will be hidden in the AI list. By hand:"
    say "  1. make an empty file named devmode.txt in $DATA"
    say "  2. start BAR, open Settings > Developer and untick 'Simple AI list'"
fi
echo
say "Start BAR. In a lobby, Add AI and pick $SHORT $VARIANT."
say "Only the player hosting the game needs this. After a BAR engine update, run install.sh again."
