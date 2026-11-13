# Library pagination increment

The library browse view requests 50 items at a time plus one lookahead, with
previous and next controls. Search is a separate existing query limited to 100
matches, and the UI says so. A failed page can be retried or the user can return
to the previous page; changing the search resets browse to the first page.
Explicit library refresh invalidates cached pages.

Pagination uses SQL offsets, not a snapshot. Insertions or deletions between
page requests can shift items and cause skips or repeats; return to the first
page to refresh the view. Queries still run synchronously on the Dart-side
repository, and search is not paginated. This does not establish large-library
performance, background work or completion of C1. Device-scale measurement and
stable snapshot/keyset navigation remain open.
