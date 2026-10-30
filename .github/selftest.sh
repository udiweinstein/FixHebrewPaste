#!/bin/bash
# בדיקות עצמיות לאפליקציה הבנויה — התוצאות מופיעות גם כהערות (annotations) בהרצה
set -e
BIN=FixHebrewPaste.app/Contents/MacOS/FixHebrewPaste

note() { local msg="${2//$'\n'/%0A}"; echo "::notice title=$1::$msg"; }

note "Version" "$($BIN --version) — $(lipo -archs "$BIN")"

OCR_OUT="$($BIN --ocr-selftest)"
echo "$OCR_OUT"
note "OCR self-test" "$OCR_OUT"

HTML_OUT="$(printf '<p>הפרויקט ב-GitHub הוא JS Paint (Pixel-perfect).</p>' | $BIN --cli-html)"
echo "$HTML_OUT"
note "HTML fix" "$HTML_OUT"
