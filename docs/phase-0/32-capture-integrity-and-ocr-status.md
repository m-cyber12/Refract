# Capture integrity and no-text PDF handling

This increment addresses three independent capture concerns:

1. Android CSV emulator CI `42968462415` failed after it reached the saved
   CSV's Reader screen: the new test incorrectly waited for Home. The fixture
   now waits for Reader before comparing saved bytes. This explains that failure,
   but a corrected test run is needed before claiming the byte comparison passed.
   Flutter `42968462572`, Rust `42968462503`, unsigned iOS `42968462573` and
   docs `42968462421` passed for the handoff change. Real-device and share-sheet
   tests remain open, as do earlier unexplained Android smoke failures.
2. Saving an edited shared draft, or a replacement selected in its editor, no
   longer deletes the original shared draft. Unchanged content and format may
   be removed after the save/reuse succeeds. On iOS the consented staged copy
   stays until the user saves the unchanged original or explicitly discards it;
   on Android the retained draft is still process-memory-only and can be lost.
   Capture jobs recovered outside this editor may leave redundant copies. No
   stronger persistence, app encryption or secure erasure is implied.
3. A PDF with no extractable text gets a clear error: it could contain scanned
   imagery or unsupported encoding, and OCR is not yet available. This is not a
   reliable scan detector; the PDF is not saved by the failed capture. A
   synthetic no-text PDF and parser/store tests exercise this path. OCR, original-
   only saving and original-layout viewing remain future work, not implemented.

CI and physical-device validation of these new changes remain necessary.
