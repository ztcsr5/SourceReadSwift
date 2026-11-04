# Reading Desk Song Regular

This OFL 1.1 derivative is only a fallback for home reading titles when iOS
cannot resolve Songti SC Regular. SwiftUI's system serif alone can render
Chinese with a sans-serif fallback. No runtime font download is required.

- Upstream: Google Fonts Noto Serif SC 2.003-H1 at commit
  8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5, ofl/notoserifsc/NotoSerifSC[wght].ttf.
- Upstream SHA256: 050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9.
- Changes: instantiate weight 400, use existing typographic line metrics, subset
  to GB2312 and Latin/punctuation, and rename to Reading Desk Song Regular.
  Glyphs outside the subset use OS font fallback.
- Generated size: 3,268,332 bytes; 7,851 mapped codepoints.
  SHA256 c99d12e49f7604017c83b0dd569b7966657fda9bab6660dda49fa1abca533264.
- Rebuild with scripts/build_reading_desk_font.py (FontTools 4.68.0, maintainer-only).
  No new Swift or CI dependency.
- Redistribution license: ReadingDeskSong-Regular-OFL.txt.
