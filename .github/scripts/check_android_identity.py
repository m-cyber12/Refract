"""Verify the APK actually launches the custom native share receiver."""
import os
import re
import subprocess
import sys
from pathlib import Path


def verify(apk):
    sdk = Path(os.environ.get("ANDROID_HOME") or os.environ["ANDROID_SDK_ROOT"])
    candidates = list((sdk / "build-tools").glob("*/aapt"))
    if not candidates:
        raise RuntimeError("Android aapt not installed")
    aapt = str(sorted(candidates)[-1])
    badging = subprocess.check_output([aapt, "dump", "badging", apk], text=True)
    if not re.search(r"^package: name='dev\.refract'", badging, re.M):
        raise ValueError("Wrong application ID: native receiver must be dev.refract")
    if "launchable-activity: name='dev.refract.MainActivity'" not in badging:
        raise ValueError("Launcher must use the custom dev.refract.MainActivity")
    manifest = subprocess.check_output([aapt, "dump", "xmltree", apk, "AndroidManifest.xml"], text=True)
    for required in ["android.intent.action.SEND", "android.intent.action.SEND_MULTIPLE", "text/plain", "text/markdown", "text/html", "application/pdf"]:
        if required not in manifest:
            raise ValueError(f"Required Android share filter absent: {required}")
    print("Verified APK identity, native launcher and supported share filters")


if __name__ == "__main__":
    verify(sys.argv[1])
