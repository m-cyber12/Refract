"""Fail the packaging gate if any required Rust ABI entry is absent/wrong.
Usage: python check_android_native.py path.apk arm64-v8a [armeabi-v7a ...]
"""
import struct
import sys
import zipfile

EXPECTED = {"arm64-v8a": (2, 183), "armeabi-v7a": (1, 40), "x86_64": (2, 62)}


def verify(apk, abis):
    with zipfile.ZipFile(apk) as bundle:
        for abi in abis:
            name = f"lib/{abi}/librefract.so"
            info = bundle.getinfo(name)  # Missing entry is an error, not an echoed notice.
            with bundle.open(name) as library:
                header = library.read(20)
            elf_class, machine = EXPECTED[abi]
            if (len(header) != 20 or header[:4] != b"\x7fELF"
                    or header[4] != elf_class or header[5] != 1
                    or struct.unpack_from("<H", header, 18)[0] != machine):
                raise ValueError(f"Invalid native ELF/architecture: {name}")
            print(f"Verified {name}: {info.file_size} bytes")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("Provide APK and required ABIs")
    verify(sys.argv[1], sys.argv[2:])
