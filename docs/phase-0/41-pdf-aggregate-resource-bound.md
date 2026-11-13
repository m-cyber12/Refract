# PDF aggregate decoded-content bound

PDF capture now rejects an empty page tree separately from the textless-page
case. It also rejects a document when the sum of decoded page content exceeds
32 MiB, even if each page remains under the existing 16 MiB per-page limit.
The whole capture fails instead of saving partial text or an original. Review
still warns that no OCR is available and extraction may be incomplete.

Synthetic fixtures exercise the zero-page and cumulative limits, and a capture
regression test checks that exceeding the aggregate limit does not save an item.
Counting occurs after the parser decodes a page, and the library may allocate or
consume CPU earlier or elsewhere. It is not a hard memory/time limit or parser
sandbox. Physical-device, adversarial, lifecycle and independent security tests
remain required; original-only save and OCR are not implemented by this change.
