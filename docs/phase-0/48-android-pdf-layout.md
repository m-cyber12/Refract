# Android PDF original-layout increment

For a saved PDF, the reader offers an explicitly approved local original-layout
view. The verified-original read checks the stored original's size and hash
before the bytes reach Android's `PdfRenderer`. One page is rendered at a time,
with a 10 MiB input limit, at most 200 pages, a 1200 by 1600 pixel bitmap bound,
and an 8 MiB PNG output limit. The user can navigate pages or close the view;
extracted text remains separately labeled. The original is not modified.

This is an increment toward A7, not completion of v1. It is not the default
first view, a parser process sandbox, OCR, password support, signature validation
or proof of authenticity. Rendering may fail on unsupported or damaged files.
There are no hard memory or time guarantees around the Android platform parser.
The viewer makes memory copies and creates a private cache file, unlinked before
parsing; interruption before unlink can leave a copy, and deletion is not secure
erasure. OS backups or forensic recovery may retain copies. The UI explains these
risks before starting. Physical-device, accessibility, interruption, hostile PDF
and independent security testing remain open.
