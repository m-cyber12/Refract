# A7 — explicitly export a stored PDF original

The PDF reader offers **Export a copy of the original**. Before reading the
original, it explains that a chosen destination/provider can receive the entire
file, including private metadata, embedded scripts and potentially cloud-backed
copies. The user must approve, then select a destination in the mobile OS picker.
No external app is opened automatically. The picker can cancel or fail; the UI
reports only what the system says and advises checking the destination. A
provider/plugin may create temporary files before cancellation; deletion is not
secure erasure. Exporting does not delete or replace the library original.

The native read path requires explicit approval, a valid existing ready item,
matching original metadata and actual SHA-256, a regular file and at most 10 MiB.
It derives the local path from the item ID rather than following the database's
stored path. On Unix, final-component symlinks are refused. These are local
consistency checks, **not proof of authenticity or a complete filesystem security
boundary**. Data crosses the native bridge as base64, creating in-memory copies.
The exported copy may be unencrypted and outside REFRACT's control. Only PDFs
are surfaced in the UI; the generic read API does not itself choose a destination.

This does **not** implement an in-app original-layout viewer, OCR, password
support, parser isolation, external document verification, automatic cloud backup,
or secure deletion. The current reader still shows extracted text first. File
picker/provider behavior, interrupted writes, permission handling, accessibility,
signed builds and physical devices require testing before release.

Tests cover approval gating, exact bytes, tampered/missing/oversized originals,
Unix final symlinks, bridge behavior, cancellation and no picker on read failure.
They do not replace physical OS picker and provider testing. CI results must be
checked on the implementation before claiming them as passed.

Additional widget regression tests exercise rejection of a mismatched source type
or reported length, suppression of duplicate exports while the destination picker
is pending, and qualified success messaging. These use a simulated destination;
they do not establish real provider behavior.

Consent is bound to the item and extension displayed when the confirmation opens.
If the widget changes to another item while confirmation or native reading is
pending, it does not open a destination picker for that stale operation. A picker
already handed to the OS cannot be recalled by this check; its result is not
reported as belonging to a different item. Widget tests cover the pre-picker races.
