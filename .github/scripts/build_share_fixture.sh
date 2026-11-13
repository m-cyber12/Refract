#!/usr/bin/env bash
# Standalone synthetic sender APK; never included in the product APK.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:?Android SDK required}}"
tools="$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
jar="$sdk/platforms/android-34/android.jar"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/classes" "$work/dex" "$work/assets"
printf '\357\273\277# Shared Markdown fixture\n\nExact synthetic share bytes.\n' > "$work/assets/fixture.md"
cp "$root/shared/fixtures/capture/compressed-text.pdf" "$work/assets/fixture.pdf"
javac -source 8 -target 8 -classpath "$jar" -d "$work/classes" "$root"/.github/fixtures/android-share/*.java
"$tools/d8" --lib "$jar" --output "$work/dex" "$work"/classes/dev/refract/sharefixture/*.class
"$tools/aapt" package -f -M "$root/.github/fixtures/android-share/AndroidManifest.xml" -I "$jar" -A "$work/assets" -F "$work/unsigned.apk"
(cd "$work/dex" && "$tools/aapt" add "$work/unsigned.apk" classes.dex)
"$tools/zipalign" -f 4 "$work/unsigned.apk" "$work/aligned.apk"
keytool -genkeypair -keystore "$work/key.jks" -storepass android -keypass android -alias fixture -keyalg RSA -validity 2 -dname 'CN=Synthetic CI fixture' -noprompt
"$tools/apksigner" sign --ks "$work/key.jks" --ks-pass pass:android --out /tmp/refract-share-fixture.apk "$work/aligned.apk"
echo 'Synthetic sender built: /tmp/refract-share-fixture.apk'
