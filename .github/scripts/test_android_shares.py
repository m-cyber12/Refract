"""Real Android share sender/provider -> MethodChannel -> UI review -> native save.
Synthetic fixture data only. Never install the fixture APK in a release build.
"""
import hashlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path


def adb(*args, binary=False):
    result = subprocess.run(["adb", *args], check=True, capture_output=True, timeout=40)
    return result.stdout if binary else result.stdout.decode().strip()


def tree():
    adb("shell", "uiautomator dump /sdcard/refract-share-ui.xml")
    raw = adb("exec-out", "cat", "/sdcard/refract-share-ui.xml")
    Path("/tmp/refract-share-ui.xml").write_text(raw)
    root = ET.fromstring(raw)
    if any("System UI isn't responding" in label(n) for n in root.iter("node")):
        raise RuntimeError("Emulator System UI ANR: infrastructure unhealthy; share delivery is not validated")
    return root


def label(node):
    return node.get("text", "") + " " + node.get("content-desc", "")


def find(text, root):
    return [n for n in root.iter("node") if text in label(n)]


def rect(node):
    return list(map(int, re.findall(r"\d+", node.get("bounds", ""))))


def tap_node(node):
    x1, y1, x2, y2 = rect(node)
    assert x2 > x1 and y2 > y1, label(node)
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    time.sleep(0.5)


def swipe():
    size = re.findall(r"\d+", adb("shell", "wm size"))
    w, h = map(int, size[-2:])
    adb("shell", "input", "swipe", str(w // 2), str(h * 3 // 4), str(w // 2), str(h // 3), "350")


def wait(text, scroll=False, attempts=16):
    for _ in range(attempts):
        root = tree()
        nodes = find(text, root)
        if nodes:
            return nodes[0]
        if scroll:
            swipe()
        time.sleep(0.5)
    raise AssertionError(f"UI did not expose {text!r}; last XML in artifact")


def tap(text, scroll=False):
    tap_node(wait(text, scroll))


def send(mode):
    adb("shell", "am", "start", "-n", "dev.refract.sharefixture/.Sender", "--es", "mode", mode)


def originals():
    output = adb("shell", "run-as dev.refract find . -name '*.original'")
    return [line.strip() for line in output.splitlines() if line.endswith(".original")]


def review_file(name):
    wait(name, scroll=True)
    root = tree()
    top = rect(find(name, root)[0])[1]
    buttons = [n for n in find("Review this draft", root) if rect(n)[1] >= top]
    if not buttons:
        swipe()
        return review_file(name)
    tap_node(min(buttons, key=lambda n: rect(n)[1]))


def main():
    adb("install", "-r", "/tmp/refract-share-fixture.apk")
    adb("shell", "pm", "clear", "dev.refract")
    adb("logcat", "-c")
    send("cold")
    wait("1 shared drafts")
    assert originals() == [], "Cold delivery must not persist originals"
    tap("Review shares")
    tap("Review this draft", scroll=True)
    wait("Cold start synthetic shared text", scroll=True)
    assert originals() == [], "Opening a draft must not save it"
    send("warm")
    wait("2 shared drafts")
    assert find("Cold start synthetic shared text", tree()), "Warm share replaced the open draft"
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    send("multiple")
    wait("4 shared drafts")
    assert originals() == [], "Suspended/multiple delivery must not save sources"
    tap("Review shares")
    # Remove the two text drafts; file items remain in their original order.
    tap("Discard draft", scroll=True)
    tap("Discard draft", scroll=True)
    wait("2 shared drafts")
    review_file("fixture.pdf")
    tap("Preview without saving", scroll=True)
    wait("Binary PDF capture regression", scroll=True)
    assert originals() == [], "Preview must not persist PDF bytes"
    tap("Save reviewed capture", scroll=True)
    tap("Approve durable save")
    wait("1 shared drafts")
    saved = originals()
    assert len(saved) == 1, saved
    source = adb("exec-out", "run-as", "dev.refract", "cat", saved[0], binary=True)
    expected = Path("shared/fixtures/capture/compressed-text.pdf").read_bytes()
    assert hashlib.sha256(source).digest() == hashlib.sha256(expected).digest(), "Original PDF bytes changed"
    # Shared Markdown still waits; a denied grant and oversized/unsupported input
    # produce explicit errors rather than a new saved original.
    send("clip")
    send("urlclip")
    wait("3 shared drafts")
    send("denied")
    send("oversize")
    send("unsupported")
    wait("6 shared drafts")
    tap("Review shares")
    wait("Shared file could not be read", scroll=True)
    assert len(originals()) == 1
    # Process death discards unreviewed input, not the already approved library item.
    adb("shell", "am", "force-stop", "dev.refract")
    adb("shell", "am", "start", "-n", "dev.refract/.MainActivity")
    wait("Import content")  # Require Flutter Home, not a splash screen or crashed process.
    root = tree()
    assert not find("Review shares", root), "Unreviewed input unexpectedly survived process death"
    assert len(originals()) == 1, "Saved original did not survive restart"
    print("PASS: cold/warm/suspended intake, multiple content grants, explicit PDF review/save, byte identity, rejected providers/formats/size, and ephemeral restart boundary")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        summary = str(error)
        evidence = Path("/tmp/refract-share-ui.xml")
        if evidence.exists():
            try:
                summary += " | Last UI labels: " + " | ".join(label(n) for n in ET.fromstring(evidence.read_text()).iter("node") if label(n).strip())
            except ET.ParseError:
                pass
        escaped = summary[:6000].replace("%", "%25").replace("\n", "%0A").replace("\r", "%0D")
        print(f"::error title=android-share::{escaped}", flush=True)
        raise
    finally:
        subprocess.run(["adb", "shell", "screencap", "-p", "/sdcard/refract-share.png"], check=False, timeout=30)
        subprocess.run(["adb", "pull", "/sdcard/refract-share.png", "/tmp/refract-share.png"], check=False, timeout=30)
        logs = subprocess.run(["adb", "logcat", "-d"], capture_output=True, check=False, timeout=30)
        Path("/tmp/refract-share-logcat.txt").write_bytes(logs.stdout)
