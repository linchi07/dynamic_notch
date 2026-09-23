#!/usr/bin/env bash
#
# Repair and verify the code signature of a built macOS .app so that it can pass
# Apple notarization.
#
# Why this exists
# ---------------
# Notarization requires *every* Mach-O binary in the bundle to be signed with
# the hardened runtime and a secure timestamp. Two files in this repo break that
# rule and Xcode does not fix them for us:
#
#   mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter
#       flags=0x2(adhoc) - no hardened runtime. It *is* re-signed on copy
#       (CodeSignOnCopy in the Embed Frameworks phase), but only with the
#       identity, not with --options runtime.
#
#   mediaremote-adapter/MediaRemoteAdapterTestClient
#       flags=0x20002(adhoc,linker-signed) - no hardened runtime, no timestamp,
#       and it lands in Contents/Resources, which Xcode never signs at all.
#
# Without this pass notarytool answers "Invalid" with:
#   "The executable does not have the hardened runtime enabled."
#   "The signature does not include a secure timestamp."
#
# Both files link only against Apple system frameworks (Foundation, AppKit,
# MediaPlayer, JavaScriptCore, ...), and the adapter framework is dlopen'ed by
# /usr/bin/perl, which itself carries flags=0x0(none) - i.e. it enforces no
# library validation. So adding the hardened runtime to them is safe and does
# not break the MediaRemote adapter.
#
# Usage
#   scripts/sign_nested_and_verify.sh fix    <path/to/App.app> "<signing identity>"
#   scripts/sign_nested_and_verify.sh verify <path/to/App.app> [--verbose]
#
# `fix` re-signs only the binaries that fail the check, then re-seals the
# enclosing bundles bottom-up and finally the app itself (entitlements are read
# back out of the existing signature so they survive the re-sign). `verify`
# changes nothing and exits non-zero listing any offender.
#
set -euo pipefail

IDENTITY_FALLBACK="Developer ID Application"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

MODE="${1:-}"
APP="${2:-}"
case "$MODE" in
  fix)
    IDENTITY="${3:-}"
    [ -n "$IDENTITY" ] || die "fix mode needs a signing identity, e.g. \"$IDENTITY_FALLBACK: Your Name (TEAMID)\""
    ;;
  verify)
    IDENTITY=""
    ;;
  -h|--help|help|"")
    usage 0
    ;;
  *)
    die "unknown mode '$MODE' (expected 'fix' or 'verify')"
    ;;
esac

[ -n "$APP" ] || die "path to the .app is required"
[ -d "$APP" ] || die "not a directory: $APP"
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Print every Mach-O file inside the bundle, one per line.
macho_files() {
  find "$APP" -type f -print0 | while IFS= read -r -d '' f; do
    case "$f" in
      */_CodeSignature/*) continue ;;
    esac
    if file -b "$f" 2>/dev/null | grep -q 'Mach-O'; then
      printf '%s\n' "$f"
    fi
  done
}

# codesign -d writes to stderr; capture both.
signature_info() {
  codesign -d --verbose=4 "$1" 2>&1 || true
}

# Compliant = hardened runtime flag present AND a secure timestamp recorded.
is_compliant() {
  local info
  info="$(signature_info "$1")"
  printf '%s\n' "$info" | grep -q 'flags=.*runtime' || return 1
  printf '%s\n' "$info" | grep -q '^Timestamp=' || return 1
  return 0
}

# Outermost bundle *below* the app that contains $1 (framework/xpc/app/bundle/plugin).
# Empty when the file is loose inside the app (e.g. Contents/Resources/*).
enclosing_bundle() {
  local p out=""
  p="$(dirname "$1")"
  while [ -n "$p" ] && [ "$p" != "/" ] && [ "$p" != "$APP" ]; do
    case "$p" in
      *.framework|*.xpc|*.app|*.bundle|*.plugin) out="$p" ;;
    esac
    p="$(dirname "$p")"
  done
  printf '%s' "$out"
}

# Sign one path, re-using whatever entitlements it already carries.
sign_path() {
  local target="$1" ent
  ent="$(mktemp -t entitlements)"
  if codesign -d --entitlements :- "$target" >"$ent" 2>/dev/null && grep -q '<key>' "$ent"; then
    echo "    re-signing with preserved entitlements: $target"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" \
             --entitlements "$ent" "$target"
  else
    echo "    re-signing: $target"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$target"
  fi
  rm -f "$ent"
}

# deepest path first, so nested code is sealed before its container
by_depth_desc() {
  awk -F/ '{print NF"\t"$0}' | sort -rn -k1,1 | cut -f2-
}

# ---------------------------------------------------------------------------
# scan
# ---------------------------------------------------------------------------
echo "Scanning $APP for Mach-O binaries ..."

ALL_MACHO="$(mktemp -t macho)"
BAD_MACHO="$(mktemp -t macho_bad)"
trap 'rm -f "$ALL_MACHO" "$BAD_MACHO"' EXIT

macho_files > "$ALL_MACHO"
total="$(wc -l < "$ALL_MACHO" | tr -d ' ')"
[ "$total" -gt 0 ] || die "no Mach-O binaries found in $APP - is this really a built app bundle?"

: > "$BAD_MACHO"
while IFS= read -r f; do
  if ! is_compliant "$f"; then
    printf '%s\n' "$f" >> "$BAD_MACHO"
  fi
done < "$ALL_MACHO"

bad_count="$(wc -l < "$BAD_MACHO" | tr -d ' ')"
echo "  $total Mach-O binaries, $bad_count without hardened runtime + timestamp"

if [ "$bad_count" -gt 0 ]; then
  echo "  offenders:"
  sed 's/^/    /' "$BAD_MACHO"
fi

if [ "$MODE" = "verify" ]; then
  if [ "$bad_count" -gt 0 ]; then
    cat >&2 <<EOF

Notarization would be rejected. Every binary above needs:
    codesign --force --options runtime --timestamp --sign "<identity>" <path>
followed by re-signing the enclosing bundle and then the app itself, because
re-signing nested code invalidates the outer seal. Run this script in 'fix' mode
to do that in the right order.
EOF
    exit 1
  fi
  echo "OK - every Mach-O binary is hardened and timestamped."
  exit 0
fi

# ---------------------------------------------------------------------------
# fix
# ---------------------------------------------------------------------------
if [ "$bad_count" -eq 0 ]; then
  echo "Nothing to repair; re-sealing the app anyway to keep the output deterministic."
else
  echo
  echo "Repairing $bad_count binaries (bottom-up) ..."

  # 1. the binaries themselves, deepest first
  by_depth_desc < "$BAD_MACHO" > "$BAD_MACHO.sorted"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sign_path "$f"
  done < "$BAD_MACHO.sorted"

  # 2. their enclosing bundles, deepest first
  : > "$BAD_MACHO.bundles"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    b="$(enclosing_bundle "$f")"
    [ -n "$b" ] && printf '%s\n' "$b" >> "$BAD_MACHO.bundles"
  done < "$BAD_MACHO.sorted"
  if [ -s "$BAD_MACHO.bundles" ]; then
    by_depth_desc < "$BAD_MACHO.bundles" | awk '!seen[$0]++' > "$BAD_MACHO.bundles.sorted"
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      sign_path "$b"
    done < "$BAD_MACHO.bundles.sorted"
  fi
  rm -f "$BAD_MACHO.sorted" "$BAD_MACHO.bundles" "$BAD_MACHO.bundles.sorted"
fi

# 3. the app itself, last. Read its entitlements back out of the existing
#    signature instead of the .entitlements file: that file still contains
#    $(PRODUCT_BUNDLE_IDENTIFIER) placeholders, and signing with unexpanded
#    placeholders would silently break Sparkle's mach-lookup exceptions.
echo
echo "Re-sealing the app bundle ..."
APP_ENT="$(mktemp -t app_entitlements)"
if codesign -d --entitlements :- "$APP" >"$APP_ENT" 2>/dev/null && grep -q '<key>' "$APP_ENT"; then
  echo "    entitlements recovered from the existing signature ($(grep -c '<key>' "$APP_ENT") keys)"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
           --entitlements "$APP_ENT" "$APP"
else
  echo "    no entitlements on the existing signature"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
rm -f "$APP_ENT"

# ---------------------------------------------------------------------------
# re-verify
# ---------------------------------------------------------------------------
echo
echo "Re-verifying ..."
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

macho_files > "$ALL_MACHO"
: > "$BAD_MACHO"
while IFS= read -r f; do
  is_compliant "$f" || printf '%s\n' "$f" >> "$BAD_MACHO"
done < "$ALL_MACHO"

if [ -s "$BAD_MACHO" ]; then
  echo "STILL NOT COMPLIANT after repair:" >&2
  sed 's/^/  /' "$BAD_MACHO" >&2
  exit 1
fi

echo "OK - $(wc -l < "$ALL_MACHO" | tr -d ' ') binaries verified, all hardened and timestamped."
