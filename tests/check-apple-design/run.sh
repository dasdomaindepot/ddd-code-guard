#!/usr/bin/env bash
# Selbsttest für den beratenden Apple-HIG-Check; alle Projekte entstehen zur Laufzeit.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/claude/skills/code-quality/bin/check-apple-design"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
RC=0
OUT=""
run() { if OUT="$($SCRIPT "$1" 2>&1)"; then RC=0; else RC=$?; fi; }
expect() {
    local wanted="$1"; shift
    if [ "$RC" -ne "$wanted" ]; then printf 'Exit %s statt %s:\n%s\n' "$RC" "$wanted" "$OUT" >&2; exit 1; fi
    for term in "$@"; do
        if ! grep -qF -- "$term" <<< "$OUT"; then printf 'Fehlt: %s\n%s\n' "$term" "$OUT" >&2; exit 1; fi
    done
}
mkdir -p "$TMP/all/translations" "$TMP/all/assets"
cat > "$TMP/all/assets/a.swift" <<'SWIFT'
UIScreen.main.bounds.width
if userInterfaceIdiom == .phone {}
.frame(width: 375)
glassEffect()
withAnimation { }
Text("Tiny").font(.system(size: 9))
.preferredColorScheme(.light)
SWIFT
cat > "$TMP/all/assets/a.css" <<'CSS'
.x { backdrop-filter: blur(5px); font-size: 9px; animation: pulse 2s; }
CSS
printf 'ApplePay\n' > "$TMP/all/translations/messages.yaml"
printf '<key>UIDesignRequiresCompatibility</key>\n<true/>\n' > "$TMP/all/Info.plist"
printf '<script>Dimensions.get("screen"); Platform.isPad; Animated.timing(); BlurView;</script>\n' > "$TMP/all/assets/a.tsx"
printf 'themeMode: ThemeMode.light; AnimationController(); fontSize: 8\n' > "$TMP/all/assets/a.dart"
run "$TMP/all"
expect 1 'BEFUND   [apple-design/AD1]' '[apple-design/AD2]' '[apple-design/AD3]' '[apple-design/AD4]' '[apple-design/AD5]' '[apple-design/AD6]' '[apple-design/AD7]' '[apple-design/AD9]' '[apple-design/AD10]' 'Vertiefung: /apple-design'
mkdir -p "$TMP/clean"
printf '.x { backdrop-filter: blur(2px); animation: pulse 2s; }\n@media (prefers-reduced-transparency: reduce) {}\n@media (prefers-reduced-motion: reduce) {}\n' > "$TMP/clean/a.css"
run "$TMP/clean"
expect 0 'Keine Befunde'
mkdir -p "$TMP/clean-app"
printf 'glassEffect()\nwithAnimation {}\naccessibilityReduceTransparency\naccessibilityReduceMotion\n' > "$TMP/clean-app/a.swift"
run "$TMP/clean-app"
expect 0 'Keine Befunde'
mkdir -p "$TMP/none"
printf 'hello\n' > "$TMP/none/README.txt"
run "$TMP/none"
expect 0 'ok       kein UI-Code gefunden'
mkdir -p "$TMP/excluded/node_modules"
printf 'glassEffect()\n' > "$TMP/excluded/node_modules/a.swift"
printf '.a {font-size: 8px}\n' > "$TMP/excluded/a.min.css"
run "$TMP/excluded"
expect 0 'ok       kein UI-Code gefunden'
mkdir -p "$TMP/git/node_modules" "$TMP/git/assets"
git -C "$TMP/git" init -q
printf 'ignored.css\n' > "$TMP/git/.gitignore"
printf '.x {font-size: 8px}\n' > "$TMP/git/ignored.css"
printf 'ApplePay\n' > "$TMP/git/assets/a.html"
run "$TMP/git"
expect 1 'BEFUND   [apple-design/AD1]'
if grep -qF '[apple-design/AD9]' <<< "$OUT"; then echo 'Ignorierte Datei geprüft' >&2; exit 1; fi
mkdir -p "$TMP/css" "$TMP/vue" "$TMP/range" "$TMP/dedup" "$TMP/plugins/plugins"
printf '.fa-apple-pay:before { content: "\\\\f123"; }\n.fa-cc-apple-pay:before {}\n' > "$TMP/css/all.css"
run "$TMP/css"
expect 0 'Keine Befunde'
cat > "$TMP/vue/a.vue" <<'VUE'
<style>
.fa-apple-pay:before {}
.fa-cc-apple-pay:before {}
</style>
<template><i class="fa-apple-pay"></i></template>
VUE
run "$TMP/vue"
expect 1 'BEFUND   [apple-design/AD1] a.vue:5:'
[ "$(grep -c '^BEFUND' <<< "$OUT")" -eq 1 ] || { echo 'CSS-Selektor als Befund' >&2; exit 1; }
printf 'const range = /[\\uE000-\\uF8FF]/; const reverse = /[\\uF8FF-\\uFFFF]/;\n' > "$TMP/range/jquery.validate.js"
run "$TMP/range"
expect 0 'Keine Befunde'
printf 'ApplePay &#xF8FF; fa-apple-pay\n' > "$TMP/dedup/a.html"
run "$TMP/dedup"
expect 1 'BEFUND   [apple-design/AD1] a.html:1:'
[ "$(grep -c '^BEFUND' <<< "$OUT")" -eq 1 ] || { echo 'Doppelte Zeilenbefunde' >&2; exit 1; }
printf '.fa-apple-pay:before {}\n' > "$TMP/plugins/plugins/all.css"
run "$TMP/plugins"
expect 0 'ok       kein UI-Code gefunden'
mkdir -p "$TMP/none-animation"
printf '.x { animation: none; }\n' > "$TMP/none-animation/a.css"
run "$TMP/none-animation"
expect 0 'Keine Befunde'
mkdir -p "$TMP/cap"
for i in $(seq 1 12); do printf 'ApplePay\n' > "$TMP/cap/$i.html"; done
run "$TMP/cap"
expect 1 'Hinweis  [apple-design/AD1] … und 2 weitere'
[ "$(grep -c '^BEFUND   \[apple-design/AD1\]' <<< "$OUT")" -eq 10 ] || { printf 'AD1-Deckel falsch\n%s\n' "$OUT" >&2; exit 1; }
if OUT="$($SCRIPT 2>&1)"; then RC=0; else RC=$?; fi
expect 2 'Verwendung:'
echo 'OK: alle Fälle bestanden'
