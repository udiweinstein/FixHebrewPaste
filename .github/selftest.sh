#!/bin/bash
# בדיקות עצמיות לאפליקציה הבנויה — התוצאות מופיעות גם כהערות (annotations) בהרצה
set -e
BIN=FixHebrewPaste.app/Contents/MacOS/FixHebrewPaste

note() { local msg="${2//$'\n'/%0A}"; echo "::notice title=${LABEL:+$LABEL: }$1::$msg"; }

note "Version" "$($BIN --version) — $(lipo -archs "$BIN") — macOS $(sw_vers -productVersion)"

OCR_OUT="$($BIN --ocr-selftest)"
if printf '%s' "$OCR_OUT" | grep -q $'\u200e\|\u200f'; then OCR_OUT="$OCR_OUT
[!] contains hidden bidi marks"; fi
echo "$OCR_OUT"
note "OCR self-test" "$OCR_OUT"

HTML_OUT="$(printf '<p>הפרויקט ב-GitHub הוא JS Paint (Pixel-perfect).</p>' | $BIN --cli-html)"
echo "$HTML_OUT"
note "HTML fix" "$HTML_OUT"
