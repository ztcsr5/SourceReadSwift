# 0138 · Comic reader boundaries and reference review

## Context

The requested manga work includes native interaction, source parsing, reliable images,
resume and explicit offline downloads. The reference is Aidoku's reading experience,
not a replacement of SourceRead's existing Legado JSON source protocol or novel reader.

Before inspecting implementation code, checked Aidoku's [LICENSE](https://github.com/Aidoku/Aidoku/blob/main/LICENSE)
and [README licensing section](https://github.com/Aidoku/Aidoku/blob/main/README.md#contributing)
on 2026-11-05: the application is published under GPLv3; its README separately discusses
distribution permissions and translations. No Aidoku source, assets or dependencies have
been imported into this candidate. This is a provenance record, not a legal compatibility opinion.

Its own [feature list](https://github.com/Aidoku/Aidoku#features) identifies downloads,
local CBZ files and an external WASM source system. Its [release notes](https://aidoku.app/release-notes/)
also discuss next-chapter prefetch and webtoon memory pressure. These are capability
references, not proof that SourceRead implements all Aidoku features or matches its performance.

## Options

1. Embed another manga app/source runtime. Rejected: changes the source contract and
   introduces unreviewed licensing, storage and maintenance obligations.
2. Put manga behavior into the novel WebKit reader. Rejected: image geometry, zoom and
   cursor semantics are different and should not depend on paragraph DOM indexes.
3. Keep a dedicated comic presentation and domain model while reusing established
   source transport, shelf and download boundaries. Selected.

## Decision

- `ComicContentParser` produces ordered pages and distinguishes partial continuation
  from a complete chapter. It does not decide navigation or archive completion.
- `ComicStripReaderView` owns recycled native scrolling, viewport geometry and zoom
  arbitration. Horizontal paging retains its separate native zoom presentation.
- `RemoteImageLoader` owns image request context, bounded transfers/decodes and shared
  subscribers. Presentation code does not bypass source authentication or verification.
- `ComicOfflineArchive` owns complete validated image transactions. The existing
  download coordinator owns scheduling, cancellation and task history.
- `ComicReadingPosition` owns source/chapter/image identity and a fractional reading
  line. The existing shelf persistence FIFO owns durability, including its small
  progress sidecar. Request credentials and image addresses do not enter the cursor.
- UIKit views report a nonpublished viewport anchor during scroll; UI page state
  changes only at page boundaries and durable progress is written after settling,
  backgrounding or exit. Do not fan out per-pixel scroll changes through AppState.
- No added package. Foundation, UIKit, ImageIO and CryptoKit cover this candidate;
  the existing ZIPFoundation remains available, but CBZ support is not asserted.

## Consequences and verification

The user-approved homepage and the novel engine stay intact. Source errors, partial
chapters, cancellation, changing image counts, sparse offline chapters and old shelf
JSON need independent tests. Simulator tests and screenshots do not certify iPhone
13 Pro frame times or long-session memory. CBZ, external tracking services and WASM
source migration are not silently claimed as delivered by this work.
