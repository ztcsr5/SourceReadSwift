# 0137 · Verified comic offline archives

## Context

Chapter downloads previously marked a manga chapter complete after caching its image URLs.
Neither the HTTP cache nor the inline-image LRU guarantees those image bytes remain available.
Ordinary chapter-cache cleanup must not silently discard explicit image downloads.

## Options

1. Treat URLCache/InlineImageStore as permanent offline storage. Rejected: eviction and request-context behavior do not provide completeness.
2. Add a separate download scheduler and database. Rejected: duplicates the existing coordinator, cancellation, and task history.
3. Reuse ChapterDownloadCoordinator and add a dedicated image archive. Selected.

## Decision

- Existing downloads own scheduling and cancellation. Comic completion requires a committed image archive, not a cached chapter URL.
- Store each chapter's validated images in a temporary directory, then rename the complete directory into place.
- Keep page order, byte counts and SHA-256 digests in its manifest. Verify digests when reopening or resuming a previous download.
- Persist hashed source/book/chapter identities, chapter title/index and image integrity metadata; do not persist image request headers or credentials.
- Cap an image at 24 MiB, a chapter at 256 MiB and 600 images. Failed, oversized, incomplete-pagination and cancelled downloads do not commit.
- Invalidate pending writes before explicit cleanup. Keep archives outside normal cache LRU and expose a separate offline library and cleanup action.
- Whole-book download first resolves fresh detail and follows directory pagination to the end reported by the source rules. A readable prefix, request/parse failure, loop, timeout or the 30-page safety cap cannot be represented as a whole-book download. Individual chapters can still be downloaded separately.
- Ordinary text-cache clearing cancels only chapter-cache jobs. The app's downloader and offline reader/library resolve the same archive dependency; the debug UI fixture injects a separate per-run directory and disables its source after relaunch.
- Existing optional download metadata remains decodable. Old URL-only download records are not presented as verified comic archives.
- Reuse Foundation, ImageIO and CryptoKit; no new package or storage-format migration is needed.

## Consequences

Disk use now reflects actual comic images and needs explicit cleanup. Retry re-downloads a failed chapter's images; partial staging is not a permanent download.
The library can reopen a sparse offline TOC without a network request. Sparse offsets must map back to the original chapter indexes before saving progress.
CBZ import and per-page resumable download transactions are not implied by this decision.
Native tests must cover network rejection, retry, corruption, relaunch, ordinary-cache cleanup and late responses after cancellation/clear.
