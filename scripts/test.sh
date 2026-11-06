#!/bin/bash
# Esegue i test; uso: scripts/test.sh [-only-testing:ZzzipTests/Classe]
cd "$(dirname "$0")/.."
LOG=build/test.log; mkdir -p build
xcodegen generate -q
xcodebuild -scheme Zzzip -destination 'platform=macOS' -derivedDataPath build test "$@" > "$LOG" 2>&1
RC=$?
grep -E "error:|failed|XCTAssert|Executed [0-9]+ test|TEST (SUCC|FAIL)" "$LOG" | grep -v "Unable to" | tail -40
exit $RC
