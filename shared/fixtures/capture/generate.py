"""Generate small synthetic, redistributable PDF capture regression fixtures.
Run from this directory. No private, external or downloaded document content.
"""
from pathlib import Path
import zlib

TEXT = b'Binary PDF capture regression. Synthetic local document with compressed text. '


def pdf(pages=1, corrupt_last=False, no_text=False):
    objects = {
        1: b'<< /Type /Catalog /Pages 2 0 R >>',
        4: b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    }
    content = b'q 0 0 1 rg 10 10 100 100 re f Q' if no_text else b'BT /F1 12 Tf 72 720 Td (' + TEXT * 3 + b') Tj ET'
    for key, data in [(5, content), (6, b'BT (unterminated')]:
        compressed = zlib.compress(data)
        objects[key] = b'<< /Length %d /Filter /FlateDecode >>\nstream\n' % len(compressed) + compressed + b'\nendstream'
    kids = []
    for i in range(pages):
        key = 7 + i
        kids.append(b'%d 0 R' % key)
        stream = 6 if corrupt_last and i == pages - 1 else 5
        objects[key] = b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R >>' % stream
    objects[2] = b'<< /Type /Pages /Kids [' + b' '.join(kids) + b'] /Count %d /Resources << /Font << /F1 4 0 R >> >> >>' % pages
    out = bytearray(b'%PDF-1.5\n%\xe2\xe3\xcf\xd3\n')
    offsets = {}
    for key, data in sorted(objects.items()):
        offsets[key] = len(out)
        out.extend(b'%d 0 obj\n' % key + data + b'\nendobj\n')
    start = len(out)
    out.extend(b'xref\n0 %d\n0000000000 65535 f \n' % (max(objects) + 1))
    for i in range(1, max(objects) + 1):
        out.extend(b'%010d 00000 n \n' % offsets[i] if i in offsets else b'0000000000 00000 f \n')
    out.extend(b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (max(objects) + 1, start))
    return out


for name, data in [('compressed-text.pdf', pdf()), ('no-extractable-text.pdf', pdf(no_text=True)), ('corrupt-second-page.pdf', pdf(2, True)), ('too-many-pages.pdf', pdf(201))]:
    Path(__file__).with_name(name).write_bytes(data)
