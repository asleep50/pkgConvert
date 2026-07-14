#!/usr/bin/env bash
#
# run-tests.sh - Automated test suite for pkgconvert
#
# Builds small test packages, runs conversions, and asserts the results.
# Requires: dpkg-deb, ar, tar, readelf (binutils). Safe to run anywhere;
# everything happens in a temp directory.
#
# Usage:  ./tests/run-tests.sh

set -uo pipefail

TESTDIR="$(cd "$(dirname "$0")" && pwd)"
CONVERTER="$(dirname "$TESTDIR")/pkgconvert.sh"
[ -x "$CONVERTER" ] || CONVERTER="$TESTDIR/../pkgconvert.sh"
[ -x "$CONVERTER" ] || { echo "FATAL: pkgconvert.sh not found relative to tests/"; exit 1; }

command -v dpkg-deb >/dev/null || { echo "FATAL: tests need dpkg-deb (package 'dpkg')"; exit 1; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
cd "$SANDBOX"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
check() { # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

# ---------- fixtures ----------
make_deb() { # make_deb <name> <extra-setup-function>
  rm -rf pkgroot; mkdir -p pkgroot/DEBIAN pkgroot/usr/bin
  cp /bin/ls pkgroot/usr/bin/testbin
  printf 'Package: %s\nVersion: 1.2\nArchitecture: amd64\nMaintainer: t\nDepends: libc6, libnss3, libmysterylib7\nDescription: test\n' "$1" > pkgroot/DEBIAN/control
  [ -n "${2:-}" ] && "$2"
  dpkg-deb -Zgzip --build pkgroot "$1.deb" >/dev/null 2>&1
}

add_desktop_bits() {
  mkdir -p pkgroot/usr/share/applications pkgroot/usr/share/icons/hicolor/48x48/apps
  printf '[Desktop Entry]\nType=Application\nName=T\nExec=/usr/bin/testbin\n' > pkgroot/usr/share/applications/good.desktop
  printf '[Desktop Entry]\nType=Application\nName=B\nExec=/opt/nothere/bin/x\n' > pkgroot/usr/share/applications/broken.desktop
  touch pkgroot/usr/share/icons/hicolor/48x48/apps/t.png
}

add_scripts_and_service() {
  printf '#!/bin/sh\ntrue\n' > pkgroot/DEBIAN/postinst; chmod 755 pkgroot/DEBIAN/postinst
  mkdir -p pkgroot/usr/lib/systemd/system
  printf '[Unit]\nDescription=x\n' > pkgroot/usr/lib/systemd/system/t.service
}

echo "== pkgconvert test suite =="
echo

# ---------- 1. basic conversion ----------
echo "[ conversion ]"
make_deb basic
"$CONVERTER" basic.deb --to tar.gz --yes >/dev/null 2>&1
check "deb -> tar.gz creates archive"        test -f basic-1.2.amd64.tar.gz
check "archive contains the binary"          bash -c "tar -tzf basic-1.2.amd64.tar.gz | grep -q usr/bin/testbin"

"$CONVERTER" basic-1.2.amd64.tar.gz --to deb --name basic --version 1.2 --yes >/dev/null 2>&1
check "tar.gz -> deb round trip"             test -f basic-1.2.x86_64.deb
check "round-trip deb is valid"              dpkg-deb -I basic-1.2.x86_64.deb

"$CONVERTER" basic.deb --to dir --yes >/dev/null 2>&1
check "deb -> dir extraction"                test -f basic-1.2.amd64.extracted/usr/bin/testbin

# ---------- 2. metadata & analysis ----------
echo "[ analysis ]"
OUT="$("$CONVERTER" basic.deb --to rpm --info 2>&1)"
check "reads package name"                   grep -q "Name:    basic" <<< "$OUT"
check "translates deps to fedora names"      grep -q "libnss3  ->  nss" <<< "$OUT"
check "flags unknown deps with search hint"  grep -q "libmysterylib7.*unknown" <<< "$OUT"

OUT="$("$CONVERTER" basic.deb --to rpm --distro opensuse --info 2>&1)"
check "openSUSE name translation"            grep -q "mozilla-nss" <<< "$OUT"
OUT="$("$CONVERTER" basic.deb --to rpm --distro arch --info 2>&1)"
check "arch tip appears for arch target"     grep -qi "debtap" <<< "$OUT"

# ---------- 3. desktop integration ----------
echo "[ desktop integration ]"
make_deb deskapp add_desktop_bits
OUT="$("$CONVERTER" deskapp.deb --to deb --info 2>&1)"
check "detects launchers"                    grep -qi "desktop launcher" <<< "$OUT"
check "warns on broken Exec path"            grep -q "broken.desktop" <<< "$OUT"
check "good Exec path not flagged"           bash -c "! grep -q 'good.desktop points' <<< '$OUT'"

"$CONVERTER" deskapp.deb --to deb --yes >/dev/null 2>&1
dpkg-deb -e deskapp-1.2.amd64.deb ctl 2>/dev/null
check "postinst scriptlet embedded in deb"   grep -q update-desktop-database ctl/postinst

make_deb plaincli
"$CONVERTER" plaincli.deb --to deb --yes >/dev/null 2>&1
rm -rf ctl; dpkg-deb -e plaincli-1.2.amd64.deb ctl 2>/dev/null
check "no scriptlet when no launchers"       test ! -f ctl/postinst

# ---------- 4. warnings ----------
echo "[ warnings ]"
make_deb sysapp add_scripts_and_service
OUT="$("$CONVERTER" sysapp.deb --to tar.gz --info 2>&1)"
check "warns about install scripts"          grep -q "install/remove scripts" <<< "$OUT"
check "warns about systemd services"         grep -q "systemd service" <<< "$OUT"

# ---------- 5. failure reports ----------
echo "[ failure handling ]"
rm -f pkgconvert-failure-*.md
# force a failure: request rpm in a sandbox PATH without rpmbuild
env PATH="/usr/bin:/bin" bash -c "command -v rpmbuild" >/dev/null 2>&1 && SKIP_RPM_FAIL=1 || SKIP_RPM_FAIL=0
if [ "$SKIP_RPM_FAIL" = 0 ]; then
  "$CONVERTER" basic.deb --to rpm --yes --report >/dev/null 2>&1
  check "failure report auto-generated"      bash -c "ls pkgconvert-failure-*.md"
  check "report contains error section"      bash -c "grep -q '## Error' pkgconvert-failure-*.md"
  check "report lists tool availability"     bash -c "grep -q 'rpmbuild: MISSING' pkgconvert-failure-*.md"
else
  echo "  SKIP  failure-report tests (rpmbuild present; cannot force failure)"
fi

check "invalid input rejected"               bash -c "! '$CONVERTER' /etc/hostname --to tar.gz --yes 2>/dev/null"
check "missing file rejected"                bash -c "! '$CONVERTER' nonexistent.deb --to tar.gz --yes 2>/dev/null"

# ---------- 6. quiet mode & exit codes ----------
echo "[ quiet mode & exit codes ]"
OUT="$("$CONVERTER" sysapp.deb --to tar.gz --info --quiet 2>&1)"
check "quiet hides [i] explanations"         bash -c "! grep -q '\[i\]' <<< '$OUT'"
check "quiet keeps [!] warnings"             grep -q '\[!\]' <<< "$OUT"
"$CONVERTER" nonexistent.deb --to tar.gz 2>/dev/null; RC=$?
check "bad input exits with code 2"          test "$RC" -eq 2
if [ "$SKIP_RPM_FAIL" = 0 ]; then
  "$CONVERTER" basic.deb --to rpm --yes >/dev/null 2>&1; RC=$?
  check "missing tool exits with code 3"     test "$RC" -eq 3
fi
check "--version reports version"            bash -c "'$CONVERTER' --version | grep -q pkgconvert"

# ---------- summary ----------
echo
echo "== results: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
