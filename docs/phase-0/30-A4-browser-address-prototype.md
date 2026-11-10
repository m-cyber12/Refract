# A4 — mobile browser address prototype

This is an **unpublished, unvalidated prototype**, not a shipped browser
integration or a production-ready feature. It contains no page-content capture,
selection extraction, background collection, account connection or native
messaging. The user must open the popup, explicitly ask to display the active
address, review it, and separately invoke the system share sheet. The chosen
address, including query and fragment, is disclosed to the OS share sheet and
whichever app the user selects. No REFRACT library save or fetch is automatic.
When system sharing is unavailable, the user can manually select and copy the
shown address; the extension does not write to the clipboard.

The prototype requests only `activeTab`, and has no persistent background script,
content-script injection, extension storage, telemetry, host permission or network
client. It rejects unsupported schemes, credentials and malformed or oversized
addresses. The last displayed address is a snapshot at the explicit read action;
if the tab changes, the user must request it again. All display uses text, not
HTML interpretation. An address may itself contain secrets and must not be
logged or silently sent anywhere.

## Platform investigation

- Mozilla documents that [activeTab](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/permissions)
  grants temporary access after user interaction, with browser restrictions.
  Firefox for Android compatibility, popup usability and OS sharing must be
  tested with the actual browser; this repository has not done so. Android
  native messaging examples for GeckoView do not establish a general channel
  from a standalone Firefox extension to an unrelated app.
- The [Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share)
  requires a user gesture and available platform support. Its presence in a
  particular extension popup and the resulting REFRACT share-sheet delivery are
  not established by a Node test. The fallback does not claim a direct handoff.
- Apple documents [Safari extension messaging](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension).
  A separate iOS Safari Web Extension target, entitlement/signing setup, consent
  UI and real device tests would be required. No Safari extension is implemented
  here, and no host-launch or cross-browser parity is promised.

The Firefox manifest is intentionally a local prototype and does **not** declare
Android store compatibility or a data-collection classification. Sharing a URL
outside the add-on can fall under Mozilla's disclosure rules; determine the
correct classification and obtain required user consent before publishing. Do not
claim `none` merely because transfer is local. Signing, review, distribution,
reproducible packaging, permissions, data classification, browser version
compatibility, device accessibility and adversarial testing remain open. Selected
text, full-page handoff and optional site-specific permissions require separate
review; no additional collection is authorized by this prototype.

## Validation

Five local Node tests exercise explicit-only reads, allowed payload, rejection,
fallback and clearing old selection. Local `web-ext` lint reported zero errors,
zero warnings and one notice about missing data-collection permissions. Neither
is a real browser/device, OS share-sheet or app-handoff test. No extension was
signed, published or installed on a user's device.
