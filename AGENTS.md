# Repository Guidelines

## Project Structure & Module Organization

This repository integrates PC NFS Underground 1 into the `nfsu2-web` browser runtime. It contains build tooling, runtime adapters and research for an experimental local browser build. The user has reported intro video/audio, a persisted profile and a race start; full compatibility remains unverified.

- `tools/catalog_bridge.py`: saved-catalog normalization and an optional upstream-lifter adapter.
- `tools/run_lifter_smoke.py`: focused real-lifter/native compilation check; setup in `docs/building.md`.
- `tools/fetch_upstreams.py`: pinned public source bootstrap into ignored `work/upstream/`.
- `start.sh` and `server/`: Rust `nfsu1-server` for local loopback.
- `patches/nfsu2-web/`: unified diffs applied by `tools/apply_*_profile.sh` (no string-replace Python).
- `tools/build_nfsu1_wasm.sh` and `tools/build_nfsu1_browser.py`: local Wasm/browser build; setup in `docs/building.md`.
- `tools/catalog.sh` / `tools/lift.sh`: thin wrappers around upstream Capstone/pefile Python.
- `runtime/` / `browser/`: handwritten NFSU1 host adapters; no emitted game functions.
- `profiles/`: NFSU1 configuration consumed by the runtime overlay.
- `poc/guest_abi.mjs`: original synthetic WebAssembly ABI fixture; `poc/README.md` documents its limits.
- `tests/`: Python catalog tests and Node.js Wasm tests.
- `docs/settings.md`: browser options and optional fonts.
- `docs/source-manifest.json` and `docs/source-permissions.md`: pinned evidence, permissions and attribution.

## Development & Test Commands

Use Python 3.10+ and Node.js 20+. Core tests require no external packages:

```sh
python3 -m unittest discover -s tests -v
node --test tests/guest_abi.test.mjs
mkdir -p out
python3 tools/catalog_bridge.py --catalog /path/to/catalog.json --output out/catalog-plan.json
```

The optional `--upstream-smoke /path/to/nfsu2-web` mode requires that source snapshot's Python dependencies. Full local builds also require matching private game inputs and a WASI SDK; see `docs/building.md`. Dependency-free tests do not exercise the game.

## Coding Style & Testing

Use four-space Python indentation, two-space JavaScript indentation, descriptive names, and existing standard-library conventions. No formatter, linter or coverage threshold is configured. Name tests `test_*.py` and `*.test.mjs`.

Keep tests to the bare minimum; no tests are needed for many changes. Prefer a focused smoke check or direct validation. Add an automated test only for a concrete, consequential risk that is difficult to verify otherwise. Avoid broad suites, coverage targets, exhaustive edge cases and tests that mirror implementation. Run only checks relevant to the change.

Distinguish synthetic checks, real upstream emission, compiled-runtime checks and browser/game validation. Never infer game compatibility from synthetic fixtures.

## Integration & Source Handling

Reuse the cached PC NFSU1 catalog and block ranges, targeting the web runtime's `CPU *` ABI. When no saved catalog exists, generate it locally with the original upstream seed/analysis pipeline, then cache it by input and tool hashes. Do not ask the user to obtain unavailable analysis artifacts or redo discovery on every build.

Keep binaries, assets, real catalogs and game-derived generated code local. Do not modify or distribute original game binaries or generated proprietary game code. Review ignored artifacts before sharing.

Do not operate a browser for testing. Give the user exact browser test instructions when a runnable build is ready; command-line compilation and focused checks may continue locally.

The user reports maintainer permission to reuse the referenced repositories with attribution. Honor that authorization without repeatedly requesting approval; preserve third-party licenses and notices. Record source reuse and revisions in the permission notes and manifest.

## Collaboration & Review

Delegate independent investigations, implementation and reviews when beneficial. Assign ownership, avoid overlapping edits, coordinate interfaces, and integrate findings. Choose suitable models/reasoning when supported. Continue without repeating completed research.

Use imperative commit subjects. PRs should explain changes and list validation and limitations.

<!-- entire-agent:begin -->
Read .entire/agent-guide.md for this repository's workflow, source inspection, and verification guidance.
@.entire/agent-guide.md
<!-- entire-agent:end -->
