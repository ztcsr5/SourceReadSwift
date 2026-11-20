# SourceReadSwift license and attribution

SourceReadSwift (纸间) is distributed as a covered work under the GNU General Public License, version 3 only (`GPL-3.0-only`). The complete terms are in [LICENSE](LICENSE). You may use, modify and redistribute it under those terms, including commercial use. The software is provided without warranty. Existing third-party copyright and license notices remain applicable; this notice does not claim authorship of those works or replace their original licenses.

## Aidoku reader adaptations

Upstream: [Aidoku/Aidoku](https://github.com/Aidoku/Aidoku), revision [`95d1468d599a154f03d6a1dd06bf839d3ff3f7bd`](https://github.com/Aidoku/Aidoku/tree/95d1468d599a154f03d6a1dd06bf839d3ff3f7bd). Its unmodified GPLv3 license is preserved in [docs/licenses/Aidoku-GPL-3.0.txt](docs/licenses/Aidoku-GPL-3.0.txt).

The following are modified versions, not unmodified Aidoku files. Adaptation notice dated 2026-11-16:

| SourceReadSwift file | Original attribution and source | Adaptation |
| --- | --- | --- |
| [ComicOffsetPreservingLayout.swift](SourceReadSwift/Features/Reader/ComicOffsetPreservingLayout.swift) | Skitty, 2023-03-01; thanks to Mantton. [VerticalContentOffsetPreservingLayout.swift](https://github.com/Aidoku/Aidoku/blob/95d1468d599a154f03d6a1dd06bf839d3ff3f7bd/Aidoku/Features/Reader/Readers/Webtoon/VerticalContentOffsetPreservingLayout.swift) | Preserves the reading anchor by stable page identity; uses the project's recycled UIKit cells, page sizes and chapter snapshots instead of Texture nodes. |
| [ComicReaderChrome.swift](SourceReadSwift/Features/Reader/ComicReaderChrome.swift) | Skitty, 2022-08-15. [ReaderToolbarView.swift](https://github.com/Aidoku/Aidoku/blob/95d1468d599a154f03d6a1dd06bf839d3ff3f7bd/Aidoku/Features/Reader/Toolbar/ReaderToolbarView.swift) | Adapts page number and remaining-page logic to the project's SwiftUI controls and settings entry. |

The JSON source engine, bookshelf and saved reading progress remain SourceReadSwift components. Aidoku's extension runner, manga artwork, branding and private Lens classes are not included in this adaptation.

## Yuedu source device identity adaptation

`SourceReadSwift/Core/JavaScript/SourceDeviceIdentity.swift` adapts `Modules/Core/RuleEngine/ModernParser/JS/DeviceIdentity.swift` from `CHANG-JUI-LIN/Yuedu-reader`, revision `cbb9a6a5d59933ecaf42c651d7f9583a34925cd1`, on 2026-11-20. The original MPL-2.0 terms are preserved in `docs/licenses/Yuedu-reader-MPL-2.0.txt`. It captures this app's vendor identifier on the main actor and exposes the captured value to the existing synchronous source bridge.

## Other components

- SwiftSoup: HTML parsing; retain its upstream copyright and license notices distributed with the package.
- ZIPFoundation: MIT License, Copyright (c) 2017–2024 Thomas Zoechling. See [upstream license](https://github.com/weichsel/ZIPFoundation/blob/0.9.19/LICENSE).
- CryptoSwift: retain its [upstream license](https://github.com/krzyzanowskim/CryptoSwift/blob/1.9.0/LICENSE), including this required acknowledgment: This product includes software developed by the "Marcin Krzyzanowski" (http://krzyzanowskim.com/).
- Sakura CSS and normalize.css in `SakuraThemeCatalog.swift`: MIT License. Copyright (c) 2016 Mitesh Shah (Sakura); Copyright © Nicolas Gallagher and Jonathan Neal (normalize.css). See [preserved notices](docs/licenses/Sakura-Normalize-MIT.txt), [Sakura upstream](https://github.com/oxalorg/sakura/blob/master/LICENSE.txt) and [normalize.css 5.0.0 upstream](https://github.com/necolas/normalize.css/blob/5.0.0/LICENSE.md). The original imported Sakura revision was not recorded, so this notice does not assert byte-for-byte equivalence to a specific release.
- Bundled fonts retain their SIL Open Font License 1.1 notices: [Ma Shan Zheng](SourceReadSwift/Resources/Fonts/MaShanZheng-Regular-OFL.txt), [Zhi Mang Xing](SourceReadSwift/Resources/Fonts/ZhiMangXing-Regular-OFL.txt), and [Reading Desk Song](SourceReadSwift/Resources/Fonts/ReadingDeskSong-Regular-OFL.txt), a renamed/subsetted derivative of Noto Serif SC.

## Source for binary distributions

When distributing an IPA, provide its complete corresponding source and build scripts under GPLv3 alongside the binary or through an equivalent, clearly identified download. Identify the exact Git revision used to build that IPA; a moving development branch alone is not a substitute for the corresponding version. Preserve applicable notices from dependencies in the distribution.

Development currently uses [ztcsr5/SourceReadSwift](https://github.com/ztcsr5/SourceReadSwift), branch `codex/next-from-build150`. The owner's authorization of 2026-11-16 supersedes earlier private-only publishing instructions. Later visibility changes do not withdraw recipients' existing GPL rights or obligations arising from earlier distribution.
