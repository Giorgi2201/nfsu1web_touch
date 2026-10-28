# Source, licenses and permission record

This page summarizes the project's source reuse and permission basis. The
[source manifest](source-manifest.json) records pinned revisions, file hashes,
and adaptation details; [upstreams.json](../profiles/upstreams.json) records
the files fetched by the build.

The project author reports that maintainers of the referenced repositories
gave permission to reuse their work with attribution. The correspondence was
not independently reviewed. This permission does not replace third-party
licenses or grant rights to game content or mod artwork.

## Source terms

| Source | Use in this project | Terms and notices |
| --- | --- | --- |
| `codepdbh/nfsu1-recompiled` | PC game analysis, sound-bank analysis/matching, and the NFSU1 widescreen port. | No root license was found at the pinned revision; reuse follows the reported maintainer permission. Credit codepdbh. |
| `th0mk/nfsu2-web` | Recompiler, runtime, browser host, and selected adapter patterns. | MIT. Portions are copyright Talha Müderrisoğlu. Keep [the notice](../patches/nfsu2-web.LICENSE). |
| `sp00nznet/pcrecomp` | Selected PE-analysis and disassembly modules used by local catalog generation. | MIT; keep [the notice](../patches/pcrecomp.LICENSE). |
| `ThirteenAG/WidescreenFixesPack` | Widescreen patch semantics and HUD layout data, through the PC project's port. | MIT; keep [the notice](../patches/WidescreenFixesPack.LICENSE). The pinned reference does not establish which revision the PC port originally used. |
| `AeroWidescreen/NFSHDContentSupport` | Font-scaling adaptations in `runtime/nfsu1_fonts.c` and `tools/font_operands.py`. | GPL-3.0-only; keep the full [license](../patches/NFSHDContentSupport.LICENSE). |
| `antoxa2584x/nfsu1-sw` | Read-only Xbox investigation. No source from this repository or its vendored Xbox runtime is included. | The game-specific repository has no root license at the inspected revision. Its separate `xboxrecomp/` license does not cover the whole repository. |
| Capstone 5.0.7 | Source build at `52c66920fc7bfa15fd9626dfd9f646c698aaa99b`. | BSD-style license and LLVM component notices are retained under ignored `work/toolchain/capstone/`. |
| pefile 2024.8.26 | Ero Carrera; source commit `4b3b1e2e568a88d4f1897d694d684f23d9e270c4`. | MIT; source and license are retained under ignored `work/toolchain/pefile/`. |
| esbuild 0.27.4 | Local browser bundler dependency. | MIT; package versions, lockfile, integrity values, and license are recorded under ignored `work/toolchain/web-bundler/` and in the source manifest. |

The optional font importer uses four DDS atlases from Raze's NFSU-HD FONTS
archive. The artwork and prepared game containers stay local under
`work/mods/`; no artwork redistribution permission is inferred. The importer
uses independently implemented readers/writers based on the format references
listed in the source manifest; it does not run ASI, Binary, or TexWizard tools.

## Adaptations and distribution

The source manifest identifies reused upstream files and blobs. Reversible
overlays adapt the pinned browser/runtime sources for the `CPU *` ABI, COM,
graphics, input, saves, date/time, audio, startup movies, and shader handling.
The input overlay extends the pinned keyboard event rings with a separate
driving stream; original physical keys and text remain available to menus and
chat. The upstream MIT notice remains in `patches/nfsu2-web.LICENSE`.
The minimap projection overlay adapts that same pinned renderer and its existing
WGSL coordinate helper. Its road-pass trace comes from read-only local PC 1.4
analysis; D9VK issue #197 is a symptom reference only, with no D9VK code reused.
The focus-loss option reuses the pinned upstream `background` setting, browser
focus events and runtime lifecycle, with Pause as the launcher default and an
exposed Keep running choice. The lifecycle overlay uses PC 1.4’s own background
polling flag instead of the NFSU2-specific Winsock startup heuristic. No
additional upstream source revision is used.
The Rust Online relay is handwritten and implements the pinned browser
runtime's kind-32 wire format. Local protocol adapters use PC 1.4 analysis;
game function bodies are not included.

Original contributions by Yurii Smetanka are MIT under the root
[LICENSE](../LICENSE), subject to the third-party terms above. This project is
unofficial and unaffiliated with EA. Use your own legally obtained game inputs.

Do not commit game executables or assets, real catalogs, bank instruction
bytes, emitted game code, prepared game containers, or compiled game modules.
`tools/fetch_upstreams.py` downloads only pinned source files into ignored
`work/upstream/`, checks Git blob hashes, and preserves originals for
reversible overlays. Review ignored files before sharing them.
