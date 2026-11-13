#!/usr/bin/env bash
# The generated shell is still temporary. Ensure regeneration didn't silently
# alter tracked native integration sources before building it in CI.
set -euo pipefail
cd "$(dirname "$0")/../.."
case "${1:-}" in
  android) paths=(apps/mobile/android/app/src/main) ;;
  ios) paths=(apps/mobile/ios/Shared apps/mobile/ios/ShareExtension apps/mobile/ios/HandoffTests apps/mobile/ios/configure_handoff.rb) ;;
  *) echo 'usage: check_native_scaffold.sh android|ios' >&2; exit 2 ;;
esac
if ! git diff --exit-code HEAD -- "${paths[@]}"; then
  echo 'Flutter scaffolding changed tracked native integration files.' >&2
  exit 1
fi
echo "Tracked $1 native integration sources unchanged by scaffolding."
