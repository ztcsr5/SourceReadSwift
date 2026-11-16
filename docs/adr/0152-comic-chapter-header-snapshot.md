# 0152 · Comic chapter header snapshots

## Context

Comic reading and offline downloads rebuilt static image headers after chapter parsing. A source's `@js:` or `<js>` header was therefore omitted even when its chapter request succeeded. Visible pages and speculative images already share each chapter's prepared `ComicImageRequest` values.

## Decision

- Resolve one image-header snapshot per chapter through `SourceImageRequestHeadersProviding`. The Legado engine owns source session state, script cache, login values and script execution; other engines retain the existing static-header fallback.
- Use the same prepared chapter requests for visible pages, horizontal prefetch and adjacent strip chapters. Resolve headers before mounting requests, and retain the current load-generation checks after asynchronous work.
- Resolve headers before offline image fetching. A resolution failure fails the chapter without fetching images or committing an archive. Existing single-page headers override chapter headers case-insensitively.
- Add session cookies for each actual HTTP image URL through the same engine's cookie store before image-cache/request identity is computed. Explicit Cookie headers, including an empty value, retain precedence. A new chapter request reads the current cookie store after logout.
- Skip header execution for chapters containing only local files or inline images. Verified offline pages remain readable without source scripts or network access.
- Private corpus image probes report header-resolution failure as a separate `image-headers` stage.
- Corpus image probes use an ephemeral session with automatic cookies and shared credentials disabled; their explicit image cookies come from that row's engine. Production image transport defaults are unchanged.

## Consequences and validation boundary

This is a chapter snapshot, not per-image signature evaluation. Headers requiring a fresh nonce, timestamp or URL signature for every image or retry have not been validated and are not claimed compatible. Such support would require resolving the actual request headers before computing image-cache and in-flight request identities.

No new dependency or archive-format migration is needed; resolved headers are not added to archive manifests. Native tests cover provider/static fallback, explicit page overrides, local-file bypass, and offline success/failure at the image-fetch boundary. Windows parser checks do not replace iOS compilation or XCTest execution.
