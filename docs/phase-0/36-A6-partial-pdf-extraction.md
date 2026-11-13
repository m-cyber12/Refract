# A6/A7 — partial PDF extraction warning

During PDF preview, the parser counts pages whose extracted text is empty. If
some pages have text and some do not, the preview warns with that count before
save. Such pages may be blank, scanned or use unsupported text encoding; the
warning does not diagnose the reason. Pages that yield some text can still be
incomplete. If the whole PDF yields no text, the existing error still blocks
capture and explains OCR is not available. No OCR runs or downloads occur.

The warning is an ephemeral review diagnostic, not currently stored as durable
per-page metadata. The reader retains its general warning that scanned portions,
images and layout may be absent. The original PDF remains unchanged when the
reviewed capture is saved. This is not original-layout viewing, a PDF
accessibility guarantee or a parser isolation boundary; those remain open.

A synthetic mixed two-page fixture and Rust plus host-native bridge tests cover
the warning, preview-before-save and byte-exact original. CI and physical-device
validation remain necessary. Batch commit `904a49b` passed Flutter `42996058922`,
Rust `42996059117` and Android emulator `42996058998`; these do not demonstrate
real multi-file provider behavior or a signed-device build.
