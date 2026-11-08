# Phase II Master — Phase 6 (CONSUMER X-RAY EXPANSION) Status

Local, source-backed consumer-document candidates: structured receipts,
subscription terms and dates, warranty/refund/cancellation/delivery clauses,
explicit review, original-byte integrity checks and cautious source comparison.

## Extraction and storage

- `evidence_engine::consumer` is a pure, deterministic English rule parser.
  Migration `0008_consumer_xray.sql` stores derived claims, scan scope, review
  transitions and explicit subscription/claim provenance links. Originals,
  prior subscriptions and legacy Proof Vault evidence remain unchanged.
- Supported explicit labels include merchant/vendor, order/receipt ID, service,
  plan, receipt total, tax and subscription price. Recognized clauses include
  renewal, trial, refunds, warranty, cancellation, delivery and order confirmation.
- Structured date fields include renewal date, trial end, warranty expiry,
  delivery date and purchase date, only when a valid ISO date has one clear
  date role in its clause. Multiple dates or roles do not silently get assigned
  a single structured date. Relative deadlines and warranty durations remain
  source clauses; no expiry is computed from a purchase or an assumed start date.
- Money uses explicit two-decimal amounts, validated thousands grouping and
  integer hundredths. The supported currency-code set is USD/EUR/GBP/RON/CAD/
  AUD/CHF (plus the unambiguous euro symbol). A bare dollar symbol does not imply
  USD; unsupported/ambiguous currency remains unspecified. Integer hundredths
  are a representation of the parsed decimal, not a claim about every currency's
  official minor-unit exponent. Ambiguous amounts remain quote-only clauses.
- Each candidate retains category, field, value/type, optional amount/currency/
  UTC date, source item ID, block index, exact supporting clause, UTF-8 byte range,
  extraction timestamp, rule version, parsed-block fingerprint, heuristic score
  and review status. Values and source quotes are not overwritten by review.
- New library captures receive best-effort consumer analysis after original
  persistence. Explicit reanalysis is idempotent for unchanged evidence and
  preserves review decisions. The bounded library backfill scans the most recent
  500 non-ignored sources. Global lists/search exclude ignored captures; explicit
  inspection of a known library source remains possible.
- The legacy Proof Vault extractor now derives quote offsets from original-text
  clause ranges rather than Unicode-lowercased byte positions. Existing stored
  Vault records are neither rewritten nor retroactively reinterpreted.

## Review, integrity and comparison

- Claims start unconfirmed. Users can confirm an extraction, reject it, or reset
  it to unconfirmed. Each actual status transition is retained in review history.
  User-confirmed does not mean independently verified or legally enforceable.
- Current parsed-source matching checks both the retained block fingerprint and
  the exact quote range. Stale evidence stays visible as historical evidence;
  it cannot be newly confirmed or silently used in a comparison/projection.
- Original-byte checks are explicit, separate operations. They compare the
  stored original file with its recorded SHA-256 hash and report unchanged
  relative to that hash, hash mismatch, or unavailable. A matching hash proves
  neither authorship/authenticity nor payment, legal validity or enforceability.
- Source comparison requires two to five distinct user-selected library items.
  Fields report the same extracted value, different extracted values, missing
  extracted fields, or unspecified currency. Every value retains its own
  passage and source link. No source is silently preferred, no exchange rate is
  inferred, and no difference is promoted into a factual contradiction or a
  conclusion that the documents concern the same transaction/product.
- Search matches field names, extracted values and supporting text, with an
  optional field/review-state filter through the API and review-state controls
  in the UI. Missing extracted information is never presented as proven absent.

## Subscription tracking is explicit

- Capturing a receipt/agreement does not automatically create or activate a
  subscription. Existing manual subscription records remain available in X-Ray.
- An explicit opt-in action creates one idempotent **imported snapshot** from
  current, user-confirmed service/subscription fields. One explicit `Service:`
  claim is required; ambiguous multiple confirmed fields, unspecified price
  currency and negative credit-like prices are not silently resolved.
- Only confirmed fields are projected. The snapshot links both to the library
  source and to the exact consumer claim IDs used. It is not proof of active
  billing. Reanalysis or later review changes do not silently rewrite an
  existing imported snapshot; the confirmation dialog explains this behavior.
- The existing upcoming-renewal and subscription views can display these
  explicitly imported records. They are not presented as externally verified.

## Mobile and interfaces

- X-Ray links to `/xray/documents`, with recent analyzed documents, claim search,
  review-state filters, a bounded backfill action and explicit source selection
  for comparison. Reader links to `/xray/document/:id` for any library source.
- Document detail shows structured values, uncertainty, exact passages, source
  block links, extraction provenance, review history and an optional original
  integrity check. Empty and partial results remain explicitly labeled.
- `/xray/compare` shows fields side by side with source IDs and independent claim
  cards. Opening a supporting source uses the existing Reader `?block=N` route.
- Additive C ABI `refract_consumer` dispatches document/scan/search/compare,
  review/history, original-check and explicit tracking actions. Dart models,
  repository methods and providers preserve native JSON/error conventions and
  input-buffer ownership. No new network or cloud dependency is introduced.

## Scope and limits

- These are English label/keyword extraction candidates, not OCR, a general
  invoice parser, a legal analysis model, or multilingual natural-language date
  understanding. No authenticity or legal-verification feature is claimed.
- Advanced consumer claims currently use **Library item source blocks**.
  Legacy Vault-only evidence keeps its existing claim view; the app does not
  pretend an externally supplied Vault text quote is newly parsed library text.
- Each analysis considers at most 500 blocks, skips blocks larger than 1 MB,
  handles up to 2000 clauses per block, skips clauses over 2000 characters and
  emits at most 100 claims per block. Skipped/limited analyses are marked partial.
- Lists return up to 200 analyzed sources; document/search views and each source
  in a comparison return at most 1000 claims. Source lists show aggregate counts
  and mark display limits. Full pagination is not implemented in this baseline.
- Recurrence rules, source applicability, whether a transaction completed,
  service activity, policy exceptions and statutory rights are not inferred.
  A keyword-containing clause can be negated or conditional; review its exact
  wording. Repeated/conflicting fields require user review rather than guessing.
- Indexing and document analysis still use synchronous mobile FFI. Large-library
  latency and physical-device interaction need further testing. No fake
  background progress, automatic calendar access, telemetry or profiling is added.

## Verification

- Local Rust/Dart syntax and SQLite schema/query preparation checks passed.
- Pure-parser regressions cover Unicode source ranges, totals, explicit and
  unknown currency, subscription frequency/dates, refund/cancellation/warranty/
  delivery clauses, invalid/ambiguous dates and bounded extraction.
- Store regressions cover idempotence, audit transitions, original preservation,
  integrity mismatch/unavailable states, search, comparisons, stale/rejected
  evidence, ignored global sources, explicit tracking, currency safeguards and
  schema-v7 upgrades without loss of subscriptions.
- Native ABI regression exercises real imports, candidates, review/history,
  scans/search, source comparison, original-byte checking, imported snapshots
  and error envelopes.
- Flutter tests cover candidate models, explicit confirmation, source-block
  navigation, opt-in integrity checks and honesty labels, comparison differences
  without a preferred source, and empty-result messaging.
- Final CI validation is pending. Emulator launch smoke does not replace manual
  consumer-document interaction or large-library testing on physical devices.
