# Minimap road rendering investigation

This is a static trace of the locally selected PC executable and the browser
renderer, not a browser/game validation. Addresses identify original routines;
no game instructions, assets or generated game code are included here.

## Verified road path

The road image comes from a track-specific texture. It is separate from the
visible world's asphalt textures and from the car/start-line marker textures.

| Site | Observed behavior |
| --- | --- |
| `0x58E540` | Initializes the map object and resolves its textures. |
| `0x58E62D`–`0x58E65B` | Formats `TRACK%d_MAP` with the track identifier, resolves it through `0x567C70` / `0x5461C0`, and stores it at map object `+0x78`. |
| `0x58E666` onward | Separately resolves `CAR_MARKER`, `CAR_MARKERB`, `TRACKMAPFRAME`, `MAPBACK`, `START_LINE`, and `BKGBMP`. |
| `0x58E8A0` / `0x58E8B6` | Draws the backing, then calls the road routine `0x58F090`; marker calls to `0x58F640` follow. |
| `0x58F090` | Builds the road quad's coordinates and texture coordinates. |
| `0x58F488` | Calls `0x590DD0` for the map's HUD-space perspective transformation. |
| `0x58F517`–`0x58F612` | Applies a separate reciprocal depth factor to each corner's three texture-coordinate components. |
| `0x58F631` | Passes the quad and the road texture from object `+0x78` to `0x58FB10`. |
| `0x58FB10` | Clips the quad to the map rectangle, interpolating its texture coordinates and alpha; emits the resulting polygon through `0x40BEF0`. |
| `0x590AAF` | Calls that submitter with `ESI = 0x61`; return address `0x590AB4` identifies this clipped-polygon submission path. |

Thus the road outline is textured geometry, with CPU clipping and projected
texture coordinates. Its source outline is not generated as road line segments
in the traced draw path. Markers also use the polygon helper, so its return
address alone does not uniquely identify roads; correlate it with the road
texture and caller `0x58F090`.

## D3D state at the polygon submitter

The `ESI == 0x61` branch of `0x40BEF0` sets stage 0 texture-transform flags
(`D3DTSS_TEXTURETRANSFORMFLAGS`, state 24) to `0x103` or `0x100`, depending on
the active graphics configuration. The first is `COUNT3 | PROJECTED`.
It selects FVF `0x10142` or `0x20142`: `XYZ`, diffuse color and one texture
coordinate set with three or four components. These are not `XYZRHW` vertices.
It supplies an identity texture transform, then calls `DrawPrimitiveUP` with
triangle-fan topology, two primitives and a 32-byte stride at `0x40C2D0`.
It restores the stage's transform flags to 2 afterward.

The packed vertex layout has position at byte 0, diffuse color at byte 12,
and texture coordinates at bytes 16/20/24/28. The submitter copies the third
texture component into the fourth slot as well. Preserving this denominator
through interpolation and applying projected sampling is necessary; reading
only the first two components loses the road mapping's perspective correction.

Texture binding and some state come through `0x40F3D0`. Alpha test is selected
from texture metadata byte `+0x55`, with reference `0xAA` when enabled. Blending
depends on metadata byte `+0x56`: zero disables blending; other values select
source-alpha/inverse-source-alpha or source-alpha/one. Z-write and cull changes
also depend on that metadata and the graphics configuration. This bounded trace
does not establish the actual loaded road texture's metadata or all inherited
depth-test, stage-operation, clipping and shader state at runtime. Those must be
captured at the road draw before claiming that they are correct or causal.

The first correction addressed the fixed vertex path discarding the third
texture component and fixed fragment shaders ignoring the projected flag.
The user reported no visible change in either map mode. That correction did
not cover the active programmable shader path established below.

## Captured shader path and declaration correction

On 2026-10-28 the user supplied a browser capture with caller `0x590AB4`,
VS 1 / PS 1, declaration `0x088004E0`, FVF `0x20142`, texture ID 387,
`PROJECTED = 0x100`, depth off, cull off, alpha test off, and normal alpha
blending. One vertex's raw texture coordinates were approximately
`(0.001367249, -0.0004582058, 0.003123707, 0.003123707)`.
Other draws from the shared helper used unit denominators for markers/backing.
The helper address alone does not establish which texture is the road.

A command-line startup shader dump using the same local build identifies
declaration `0x088004E0` as XYZ at 0, diffuse color at 12, **FLOAT2** UV at 16.
VS 1 passes its texture input through an add with constant register 4;
PS 1 already applies projected sampling. `SetFVF` updated only a number in the
host and retained this earlier declaration. Therefore the four-component map
input reached the vertex shader as `(u,v,0,1)`, losing its denominator before
the fragment shader could divide. This explains why the first fixed-function
correction did not affect the captured path.

The corrected `SetFVF` binds an immutable declaration for each of the two traced
map FVF layouts, so both the CPU interpreter and GPU translator fetch the
three/four components. Distinct declaration objects give the GPU shader cache
distinct layout keys. Explicit `SetVertexDeclaration` clears the stale FVF
shadow. Other FVF layouts are outside this focused correction.

This establishes a submitted draw and a concrete coordinate corruption on the
captured shared polygon path. After the declaration correction and rebuild
(`nfsu1-local-29bd80b573e6`), the user confirmed that the minimap works.
This is user-reported browser validation; no browser was operated by the agent.

## 2D and 3D modes

At frame start, `0x58E85A` copies the selected style from map object `+0xC0`
to `+0xC4`. The transform uses the corresponding 0x3C-byte profile starting at
`0x737850`, including its angle, perspective distance and offsets. The
initializer starts with style 6. The exact in-game 2D/3D setting-to-style mapping
has not been verified, so these styles must not yet be labeled as menu modes.

## Historical comparison and remaining validation

[D9VK issue #197](https://github.com/misyltoad/d9vk/issues/197) reports the same
visible split: missing road outline with working indicators and start/end lines.
The thread confirms rendering was fixed by October 2019, but does not identify
a fixing commit or a root cause. It supports investigating the separate road
pass; it does not establish that this runtime has the same bug.

The repository prohibits automated browser testing. Once a rebuilt local build
is ready, perform these checks manually:

1. Start one reproducible single-player race and check the road outline, car
   markers, start/finish lines and map backing independently.
2. Change the game's track-map setting between 2D and 3D. Repeat the same race
   and position; record whether roads disappear, distort or clip in either mode.
3. Drive through turns and elevation changes. Check that roads stay aligned
   with the moving markers and remain inside the map rectangle.
4. Repeat at original 4:3 and widescreen aspect ratios. Check map placement and
   clipping separately from texture projection.
5. If roads remain missing, capture the road texture identity/load status,
   caller, FVF/declaration, vertex data including the projective denominator,
   shader selection, stage operations, alpha/blend, depth, cull and scissor state
   at submission. Distinguish an absent draw from a submitted invisible draw.

Command-line synthetic checks can verify the renderer's coordinate handling;
they cannot establish minimap visibility or game compatibility.

## Local validation and capture

`python3 tools/minimap_projection_smoke.py` compiles the actual FVF declaration
builder and vertex fetch/conversion with authored projected vertices. It runs
a programmable CPU shader and inspects its translated WGSL to check that both
FVF variants retain q, then checks fixed vertex conversion and fixed fragment
projection. It does not execute the shader on a GPU.

Start with `./start.sh`, open `http://127.0.0.1:8765/`, and run the manual race
checks above. Restart the local server after rebuilding Wasm, and reload the
page before Play: the page retains its loaded module between games.

The first two executions per map style emit `[nfsu1 road-pass]` begin/end lines
around `0x58F090`, including its road texture object and submission count.
Up to four draws within each sampled road pass emit `[nfsu1 map]` lines,
including caller, texture ID, shader/declaration/FVF, raw UV/Q, topology,
target, depth, cull, clipping, blend, alpha and stage-0 operations. Markers
outside the road routine no longer consume this diagnostic's log budget.
A begin/end pair with zero submissions identifies a road pass that emitted
no draw; missing begin lines require checking the loaded build and call path.
