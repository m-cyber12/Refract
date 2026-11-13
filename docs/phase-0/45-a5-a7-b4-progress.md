# A5, A7 and B4 — incremental progress

## A5: INI intake

INI selections and recognized named shares are accepted as strict UTF-8 plain
text, subject to the existing 2 MiB limit and explicit preview/save. Syntax is
not parsed or validated, and values can contain secrets. Unedited selected text
preserves BOM and line endings; editing changes the saved original. Provider MIME
routing, caching and physical-device behavior remain outside these tests; no
universal file support is claimed.

## A7: PDF reader labeling

The reader labels available PDF blocks as extracted text and states that it does
not display original page layout. Missing blocks do not establish capture mode,
PDF validity, or authenticity. This is not original-layout viewing, OCR or
password support; physical-device and accessibility validation remain open.

## B4: scaffold overwrite guard

CI checks that Flutter project scaffolding leaves the tracked native integration
sources unchanged before continuing. This protects a limited set of tracked files;
it does not compare the generated shell itself, establish reproducibility of all
outputs, or commit maintained Gradle/Xcode projects. Migration, signing and
physical-device gates remain open.

None of these three areas is closed by this increment; the acceptance criteria
and release gates in the remaining-work inventory still apply.
