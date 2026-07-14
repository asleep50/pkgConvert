#!/usr/bin/env bash
#
# pkgconvert-gui - Simple graphical front-end for pkgconvert.sh
#
# Works on GNOME (zenity) and KDE Plasma (kdialog) — auto-detects which
# dialog tool is available, preferring the one that matches your desktop.
#
# Flow: pick a package file -> choose output format -> review the
# pre-flight analysis -> convert.
#
# Keep this script in the same folder as pkgconvert.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONVERTER="$SCRIPT_DIR/pkgconvert.sh"

# ---------- pick a dialog backend ----------
BACKEND=""
if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ] && command -v kdialog >/dev/null; then
  BACKEND="kdialog"
elif command -v zenity >/dev/null; then
  BACKEND="zenity"
elif command -v kdialog >/dev/null; then
  BACKEND="kdialog"
else
  echo "This GUI needs 'zenity' (GNOME) or 'kdialog' (KDE Plasma)." >&2
  echo "Install one:  sudo dnf install zenity   |   sudo dnf install kdialog" >&2
  echo "Or use the command line: ./pkgconvert.sh <file> --to <format>" >&2
  exit 1
fi

# ---------- dialog abstraction ----------
dlg_error() {
  case "$BACKEND" in
    zenity)  zenity --error --title="pkgconvert" --text="$1" 2>/dev/null ;;
    kdialog) kdialog --title "pkgconvert" --error "$1" 2>/dev/null ;;
  esac
}
die_gui() { dlg_error "$1"; exit 1; }

dlg_pick_file() {
  case "$BACKEND" in
    zenity)
      zenity --file-selection \
        --title="pkgconvert — choose a package to convert" \
        --file-filter="Linux packages | *.deb *.rpm *.AppImage *.appimage *.snap *.tar.gz *.tgz *.tar.xz *.tar.bz2 *.tar.zst *.tar" \
        --file-filter="All files | *" 2>/dev/null ;;
    kdialog)
      kdialog --title "pkgconvert — choose a package to convert" \
        --getopenfilename "$HOME" \
        "Linux packages (*.deb *.rpm *.AppImage *.appimage *.snap *.tar.gz *.tgz *.tar.xz *.tar.bz2 *.tar.zst *.tar);;All files (*)" 2>/dev/null ;;
  esac
}

dlg_pick_format() {
  case "$BACKEND" in
    zenity)
      zenity --list --radiolist \
        --title="pkgconvert — output format" \
        --text="Convert <b>$1</b> to:" \
        --column="" --column="Format" --column="Best for" \
        TRUE  "rpm"    "Fedora / RHEL / openSUSE" \
        FALSE "deb"    "Debian / Ubuntu / Mint" \
        FALSE "tar.gz" "Any distro (portable archive)" \
        FALSE "dir"    "Just extract to a folder" \
        --height=280 --width=460 2>/dev/null ;;
    kdialog)
      kdialog --title "pkgconvert — output format" \
        --radiolist "Convert $1 to:" \
        "rpm"    "rpm — Fedora / RHEL / openSUSE" on \
        "deb"    "deb — Debian / Ubuntu / Mint" off \
        "tar.gz" "tar.gz — any distro (portable archive)" off \
        "dir"    "dir — just extract to a folder" off 2>/dev/null ;;
  esac
}

dlg_review_analysis() {  # $1 = analysis file; returns 0 to proceed
  case "$BACKEND" in
    zenity)
      zenity --text-info \
        --title="pkgconvert — pre-flight analysis (click Convert to continue)" \
        --filename="$1" \
        --ok-label="Convert" --cancel-label="Cancel" \
        --width=680 --height=520 2>/dev/null ;;
    kdialog)
      kdialog --title "pkgconvert — pre-flight analysis" --textbox "$1" 680 520 2>/dev/null
      kdialog --title "pkgconvert" --yesno "Proceed with the conversion?" 2>/dev/null ;;
  esac
}

dlg_success() {
  case "$BACKEND" in
    zenity)  zenity --info --title="pkgconvert — done" --text="$1" --width=420 2>/dev/null ;;
    kdialog) kdialog --title "pkgconvert — done" --msgbox "$1" 2>/dev/null ;;
  esac
}

dlg_ask_yesno() {  # $1 = question; returns 0 for yes
  case "$BACKEND" in
    zenity)  zenity --question --title="pkgconvert" --text="$1" 2>/dev/null ;;
    kdialog) kdialog --title "pkgconvert" --yesno "$1" 2>/dev/null ;;
  esac
}

dlg_save_file() {  # $1 = suggested filename; prints chosen path
  case "$BACKEND" in
    zenity)  zenity --file-selection --save --title="pkgconvert — save failure report" \
               --filename="$HOME/$1" 2>/dev/null ;;
    kdialog) kdialog --title "pkgconvert — save failure report" \
               --getsavefilename "$HOME/$1" "Markdown files (*.md)" 2>/dev/null ;;
  esac
}

# Offer to save a Markdown log of a failed attempt. $1 = stage, $2 = output log file
offer_failure_report() {
  dlg_ask_yesno "The $1 failed.\n\nWould you like to save a report of this failed attempt?\n(A Markdown log you can keep, or attach to a GitHub issue.)" || return 0
  local dest
  dest="$(dlg_save_file "pkgconvert-failure-$(date +%Y%m%d-%H%M%S).md")" || return 0
  [ -n "$dest" ] || return 0
  {
    echo "# pkgconvert — failed conversion report"
    echo
    echo "- **Date:** $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo "- **System:** $(uname -srm)"
    echo "- **Input file:** \`$(basename "${INPUT:-?}")\`"
    echo "- **Requested output:** ${OUTFMT:-not chosen}"
    echo "- **Failed stage:** $1"
    echo
    echo "## Pre-flight analysis"
    echo
    echo '```'
    cat "$ANALYSIS_FILE" 2>/dev/null || echo "(analysis did not complete)"
    echo '```'
    echo
    echo "## Conversion output / error"
    echo
    echo '```'
    cat "$2" 2>/dev/null || echo "(no output captured)"
    echo '```'
    echo
    echo "_Generated by pkgconvert-gui. If you believe this failure is a bug,_"
    echo "_attach this file to an issue on the project's GitHub page._"
  } > "$dest" 2>/dev/null && dlg_success "Failure report saved:\n\n$dest"
}

# Progress: zenity gets a pulsating bar; kdialog gets a passive popup
# (kdialog progress bars need dbus plumbing — overkill for a fast task).
progress_start() {
  ZPID=""
  case "$BACKEND" in
    zenity)
      zenity --progress --pulsate --no-cancel --auto-close \
        --title="pkgconvert" --text="$1" 2>/dev/null &
      ZPID=$! ;;
    kdialog)
      kdialog --title "pkgconvert" --passivepopup "$1" 60 2>/dev/null || true ;;
  esac
}
progress_stop() {
  [ -n "${ZPID:-}" ] && { kill "$ZPID" 2>/dev/null; wait "$ZPID" 2>/dev/null; ZPID=""; }
}

# ---------- checks ----------
[ -x "$CONVERTER" ] || die_gui "Could not find pkgconvert.sh next to this script. Keep both files in the same folder."

# ---------- Step 1: pick the package file ----------
INPUT="$(dlg_pick_file)" || exit 0
[ -n "$INPUT" ] || exit 0
[ -f "$INPUT" ] || die_gui "File not found: $INPUT"

# ---------- Step 2: choose the output format ----------
OUTFMT="$(dlg_pick_format "$(basename "$INPUT")")" || exit 0
[ -n "$OUTFMT" ] || exit 0

# ---------- Step 3: run the analysis and show it ----------
ANALYSIS_FILE="$(mktemp)"
RESULT_FILE="$(mktemp)"
trap 'rm -f "$ANALYSIS_FILE" "$RESULT_FILE"' EXIT

progress_start "Analyzing package..."
"$CONVERTER" "$INPUT" --to "$OUTFMT" --info > "$ANALYSIS_FILE" 2>&1
ARC=$?
progress_stop
[ "$ARC" -eq 0 ] || { dlg_error "Analysis failed (exit code $ARC): $(tail -n 3 "$ANALYSIS_FILE")"; offer_failure_report "analysis" "$ANALYSIS_FILE"; exit 1; }

dlg_review_analysis "$ANALYSIS_FILE" || exit 0

# ---------- Step 4: convert ----------
OUTDIR="$(dirname "$INPUT")"
progress_start "Converting to $OUTFMT..."
( cd "$OUTDIR" && "$CONVERTER" "$INPUT" --to "$OUTFMT" --yes > "$RESULT_FILE" 2>&1 )
CRC=$?
progress_stop

if [ "$CRC" -eq 0 ]; then
  CREATED="$(grep -m1 -E '^Created' "$RESULT_FILE" | sed 's/^Created:* *//; s|/$||')"
  INSTALL_HINT="$(grep -m1 'Install with' "$RESULT_FILE" | sed 's/^ *//' || true)"
  dlg_success "Success!

Created: ${CREATED:-see terminal output}
Location: $OUTDIR

$INSTALL_HINT"
else
  dlg_error "Conversion failed (exit code $CRC): $(tail -n 3 "$RESULT_FILE")"
  offer_failure_report "conversion" "$RESULT_FILE"
  exit 1
fi
