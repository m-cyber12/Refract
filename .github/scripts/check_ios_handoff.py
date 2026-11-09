"""Verify unsigned embedded-target metadata and statically retained C ABI roots.
Not a signing, provisioning or physical-device/provider handoff test.
"""
import plistlib
import re
import subprocess
import sys
from pathlib import Path


def verify(path):
    app = Path(path)
    extension = app / 'PlugIns/ShareExtension.appex'
    runner_info = plistlib.loads((app / 'Info.plist').read_bytes())
    extension_info = plistlib.loads((extension / 'Info.plist').read_bytes())
    group = runner_info.get('RefractAppGroup')
    assert group and group.startswith('group.') and '$(' not in group
    assert extension_info['RefractAppGroup'] == group
    assert extension_info['CFBundleIdentifier'] == runner_info['CFBundleIdentifier'] + '.ShareExtension'
    assert extension_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.share-services'
    assert extension_info['CFBundleShortVersionString'] == runner_info['CFBundleShortVersionString']
    assert extension_info['CFBundleVersion'] == runner_info['CFBundleVersion']
    assert (extension / extension_info['CFBundleExecutable']).is_file()
    source = Path('crates/platform_bridge/src/lib.rs').read_text()
    required = set(re.findall(r'pub\s+(?:unsafe\s+)?extern\s+"C"\s+fn\s+(refract_\w+)', source))
    # Modern Flutter debug builds may place app symbols in Runner.debug.dylib.
    binaries = [app / runner_info['CFBundleExecutable']]
    binaries += list(app.glob('*.debug.dylib'))
    symbols = '\n'.join(subprocess.check_output(['nm', '-gU', str(binary)], text=True) for binary in binaries)
    missing = [name for name in required if not re.search(r'\b_' + name + r'\b', symbols)]
    assert not missing, f'Missing Rust ABI symbols: {missing}'
    print(f'PASS: embedded ShareExtension, matching group/versions, {len(required)} C ABI roots retained (unsigned build only)')


if __name__ == '__main__':
    verify(sys.argv[1])
