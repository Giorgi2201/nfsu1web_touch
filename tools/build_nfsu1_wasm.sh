#!/bin/bash
# Link the selected NFSU1 emission (GEN env or gen/nfsu1-current).
# Experimental build: remaining guest abort stubs limit compatibility.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="${UPSTREAM:-$ROOT/work/upstream/nfsu2-web}"
GEN="${GEN:-$ROOT/gen/nfsu1-current}"
ABK_GEN="${ABK_GEN:-$ROOT/gen/nfsu1-abk}"
OBJCACHE="${OBJCACHE:-$ROOT/work/objcache}"
OPT="${OPT:--O1}"
J="${J:-$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
OUT="$UPSTREAM/out/web"

if [[ -z "${WASI:-}" ]]; then
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) WASI_DIR="wasi-sdk-34.0-arm64-macos" ;;
    Darwin-x86_64) WASI_DIR="wasi-sdk-34.0-x86_64-macos" ;;
    Linux-x86_64) WASI_DIR="wasi-sdk-34.0-x86_64-linux" ;;
    Linux-aarch64) WASI_DIR="wasi-sdk-34.0-arm64-linux" ;;
    *)
      echo "error: set WASI to a WASI SDK 34 root (unsupported host $(uname -s)-$(uname -m))" >&2
      exit 1
      ;;
  esac
  WASI="$ROOT/work/toolchain/$WASI_DIR"
fi
[ -x "$WASI/bin/clang" ] || { echo "WASI clang missing: $WASI (run ./build.sh or set WASI=)"; exit 1; }
[ -f "$GEN/fntab.c" ] || { echo "missing $GEN/fntab.c (run lift_catalog.py --link-stubs)"; exit 1; }
[ -f "$GEN/decls.h" ] || { echo "missing $GEN/decls.h"; exit 1; }

mkdir -p "$UPSTREAM/gen" "$OUT/obj" "$OUT/obj/srv" "$OUT/rt" "$OBJCACHE"
ln -sfn "$GEN" "$UPSTREAM/gen/all"
mkdir -p "$UPSTREAM/gen/server"
printf '%s\n' \
  '#include "module.h"' \
  'const ModInfo g_srv_modinfo = { "server.dll", "", 0x00a00000u, 0, 0, 0, 0, 0, 0 };' \
  > "$UPSTREAM/gen/server/modinfo.c"
printf '%s\n' \
  '#include "cpu.h"' 'typedef void(*guest_fn)(CPU*);' \
  'const uint32_t g_srv_fn_count = 0;' \
  'const uint32_t g_srv_fn_addr[1] = {0};' \
  'const guest_fn g_srv_fn_ptr[1] = {0};' \
  > "$UPSTREAM/gen/server/fntab.c"
printf '%s\n' \
  '#include <stdint.h>' \
  'typedef struct { uint32_t iat; const char*dll; const char*name; int nargs; } ImpEnt;' \
  'const uint32_t g_srv_imp_count = 0;' \
  'const ImpEnt g_srv_imp[1] = {{0}};' \
  > "$UPSTREAM/gen/server/impargs.c"
printf '%s\n' '#ifndef DECLS_H' '#define DECLS_H' '#include "cpu.h"' '#endif' \
  > "$UPSTREAM/gen/server/decls.h"
echo "nfsu1-bringup" > "$UPSTREAM/gen/all/web-lift.txt"
cp -f "$ROOT/runtime/nfsu1_fonts.h" "$UPSTREAM/runtime/nfsu1_fonts.h"

cd "$UPSTREAM"
CC="$WASI/bin/clang"
OBJDUMP="$WASI/bin/llvm-objdump"
GUEST_END=671088640
INITIAL_MB="${INITIAL_MB:-1024}"
TARGET="--target=wasm32-wasip1-threads -pthread"
FEAT="-msimd128 -mbulk-memory -mnontrapping-fptoint -mtail-call -mexception-handling -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false"
DEFS="-D_WASI_EMULATED_MMAN -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS"
# Bring-up: allow experimental guest start. NFSU2 wrappers are renamed below.
EXTRA="-DNFSU1_ALLOW_EXPERIMENTAL_BOOT"
CFLAGS="$TARGET $OPT $FEAT $DEFS $EXTRA -fno-delete-null-pointer-checks -include runtime/web/compat/wasm_plat.h -Iruntime/web/compat -Iruntime -Igen/all"
SHARDFLAGS="-DNFSU2_GUEST_OBJ"
HDRSUM="$( (cat runtime/cpu.h runtime/nfsu1_profile.h runtime/web/compat/wasm_plat.h; echo "$CFLAGS $SHARDFLAGS") | shasum | cut -c1-16)"
CACHE_KEYS="$ROOT/tools/guest_object_cache.py"
NOINLINE_WRAPS='sub_0066e8b0|sub_00547db0|sub_00547dc0|sub_00548610|sub_00546d70|sub_00546e00|sub_00547ae0|sub_0054e2f0|sub_0043a220|sub_0043a830|sub_004390d0|sub_005647d0|sub_004f6360|sub_0058f090'
export CC OBJDUMP CFLAGS SHARDFLAGS OUT FULL MEMCHECK OBJCACHE HDRSUM CACHE_KEYS NOINLINE_WRAPS

{ (cd gen/all && ls shard_*.c fntab.c impargs.c $([ -f stubs.c ] && echo stubs.c) | sed "s|^|all |")
  (cd gen/server && ls fntab.c impargs.c modinfo.c | sed "s|^|server |"); } |
  xargs -P "$J" -n 2 sh -c '
  case "$1" in all) od="$OUT/obj" ;; *) od="$OUT/obj/srv" ;; esac
  src="gen/$1/$2"; obj="$od/$(basename "$2" .c).o"
  shardflags="$SHARDFLAGS"; shardhdr="$HDRSUM"
  # Preserve the clock thunk, Online callbacks and frontend switch so linker
  # wrappers also observe their intra-shard calls, including cleanup tail calls.
  if grep -Eq "^void ($NOINLINE_WRAPS)\\(" "$src"; then
    shardflags="$shardflags -fno-inline-functions"
    shardhdr="$HDRSUM-online-noinline-v3"
  fi
  keys=$(python3 "$CACHE_KEYS" "$src" "gen/$1/decls.h" "$shardhdr") || exit 1
  sum=${keys%% *}; legacy_sum=${keys#* }
  if [ -z "${FULL:-}" ] && [ -f "$obj" ] && [ "$(cat "$obj.sum" 2>/dev/null)" = "$sum" ]; then exit 0; fi
  if [ -z "${FULL:-}" ] && [ -f "$OBJCACHE/$sum.o" ]; then
    if [ ! "$OBJCACHE/$sum.o" -ef "$obj" ]; then
      ln -f "$OBJCACHE/$sum.o" "$obj" 2>/dev/null || cp "$OBJCACHE/$sum.o" "$obj" || exit 1
    fi
    echo "$sum" > "$obj.sum"; exit 0
  fi
  # Migrate only objects validated against the complete historical input hash.
  if [ -z "${FULL:-}" ]; then
    legacy_obj=""
    if [ -f "$obj" ] && [ "$(cat "$obj.sum" 2>/dev/null)" = "$legacy_sum" ]; then
      legacy_obj="$obj"
    elif [ -f "$OBJCACHE/$legacy_sum.o" ]; then
      legacy_obj="$OBJCACHE/$legacy_sum.o"
    fi
    if [ -n "$legacy_obj" ]; then
      ln -f "$legacy_obj" "$OBJCACHE/$sum.o" 2>/dev/null || cp "$legacy_obj" "$OBJCACHE/$sum.o" || exit 1
      if [ ! "$OBJCACHE/$sum.o" -ef "$obj" ]; then
        ln -f "$OBJCACHE/$sum.o" "$obj" 2>/dev/null || cp "$OBJCACHE/$sum.o" "$obj" || exit 1
      fi
      echo "$sum" > "$obj.sum"; exit 0
    fi
  fi
  o=$($CC $CFLAGS $shardflags -I"gen/$1" -Wno-unused-label -Wno-parentheses-equality -c -o "$obj" "$src" 2>&1); r=$?
  [ -z "$o" ] || printf "%s\n" "$o" | head -8
  [ $r -eq 0 ] || { echo "FAILED: $src" >&2; exit $r; }
  guestdata() { "$OBJDUMP" -r "$obj" | awk "/^RELOCATION RECORDS FOR \\[DATA\\]/ { d = 1; next } /^RELOCATION RECORDS/ { d = 0 }
    d && \$3 ~ /^g_guest[+-]/ && \$3 != \"g_guest+0\" { f = 1 } END { exit !f }"; }
  if guestdata; then
    $CC $CFLAGS $shardflags -fno-jump-tables -I"gen/$1" -Wno-unused-label -Wno-parentheses-equality -c -o "$obj" "$src" \
      || { echo "FAILED: $src" >&2; exit 1; }
    if guestdata; then echo "FAILED: $src guest addresses in data" >&2; exit 1; fi
  fi
  echo "$sum" > "$obj.sum"
  ln -f "$obj" "$OBJCACHE/$sum.o" 2>/dev/null || cp "$obj" "$OBJCACHE/$sum.o"
  echo "  compiled $src"' sh

# nfsu1_win32: original NFSU1 USER32 HLE (synced from repo runtime/ before compile).
cp -f "$ROOT/runtime/nfsu1_win32.c" "$UPSTREAM/runtime/nfsu1_win32.c"
cp -f "$ROOT/runtime/nfsu1_diagnostics.c" "$UPSTREAM/runtime/nfsu1_diagnostics.c"
cp -f "$ROOT/runtime/nfsu1_intro.c" "$UPSTREAM/runtime/nfsu1_intro.c"
cp -f "$ROOT/runtime/nfsu1_online.c" "$UPSTREAM/runtime/nfsu1_online.c"
cp -f "$ROOT/runtime/nfsu1_online_entry.c" "$UPSTREAM/runtime/nfsu1_online_entry.c"
cp -f "$ROOT/runtime/nfsu1_graphics.c" "$UPSTREAM/runtime/nfsu1_graphics.c"
cp -f "$ROOT/runtime/nfsu1_fonts.c" "$UPSTREAM/runtime/nfsu1_fonts.c"
cp -f "$ROOT/runtime/nfsu1_widescreen.c" "$UPSTREAM/runtime/nfsu1_widescreen.c"
cp -f "$ROOT/runtime/nfsu1_widescreen.h" "$UPSTREAM/runtime/nfsu1_widescreen.h"
cp -f "$ROOT/runtime/widescreen_hud.inc" "$UPSTREAM/runtime/widescreen_hud.inc"
RT="mem dispatch genexec heap watchdog win32 win32_ext nfsu1_win32 nfsu1_diagnostics nfsu1_intro nfsu1_online nfsu1_online_entry nfsu1_graphics nfsu1_fonts nfsu1_widescreen com debug res fileio overrides d3dx_hle vsemu oracle autotest lifecycle widescreen framerate dinput_pad dikeys keyboard dinput_kbd career intro drifttest roam roam_core roam_game horn carsfx racehorn winsock online netrace module modheap enhance headlights"
# Widescreen requires mid-block guest_hook sites in the selected emission.
python3 - <<'PY'
import json, pathlib, re, sys
report = pathlib.Path("gen/all/lift-report.json")
if not report.is_file():
    sys.exit("missing gen/all/lift-report.json; re-lift with --hooks-file")
data = json.loads(report.read_text())
if data.get("font_operands_version") != 2 or len(data.get("font_operand_sites", [])) != 6:
    sys.exit("re-lift with current lift_catalog.py: scoped HD font operands required")
if data.get("widescreen_operands_version") != 1:
    sys.exit("re-lift with current lift_catalog.py: scoped HUD operands required")
hooks = data.get("hooks") or []
emitted = data.get("hooks_emitted")
if emitted != len(hooks) or len(hooks) < 54:
    sys.exit(f"incomplete widescreen hooks in lift report: emitted={emitted} listed={len(hooks)}")
text = "\n".join(p.read_text() for p in sorted(pathlib.Path("gen/all").glob("shard_*.c")))
if any(f"nfsu1_font_dimension(c->{reg}, {axis}u)" not in text
       for reg in ("ecx", "edx") for axis in (0, 1)):
    sys.exit("incomplete HD font dimension accessors in selected emission")
if "nfsu1_font_mip_reduction(c->esi)" not in text:
    sys.exit("missing HD font upload mip policy")
missing = [va for va in hooks
           if f"guest_hook(c, 0x{int(va, 16):x}u)" not in text]
if missing:
    sys.exit("missing guest_hook emission for: " + ", ".join(missing))
print(f"widescreen hooks present: {len(hooks)}")
PY
WEB="$(cd runtime/web && ls *.c | sed 's/\.c$//')"
ABK_OBJS=()
if [ -f "$ABK_GEN/report.json" ]; then
  # Check complete private emission before compiling any bank-derived source.
  python3 - "$ABK_GEN" <<'PY'
import hashlib, json, sys
from pathlib import Path
folder = Path(sys.argv[1])
report = json.loads((folder / "report.json").read_text())
if report["status"] != "emission_complete":
    raise ValueError("incomplete ABK emission")
for name in ("abk_decls.h", "abk_functions.c", "abk_tables.c", "blocks.c"):
    if hashlib.sha256((folder / name).read_bytes()).hexdigest() != report["outputs"][name]:
        raise ValueError("ABK output hash mismatch: " + name)
PY
  cp -f "$ROOT/runtime/nfsu1_abk.c" "$ROOT/runtime/nfs_abk.h" runtime/
  RT="$RT nfsu1_abk"
  mkdir -p "$OUT/obj/abk"
  for f in abk_functions abk_tables blocks; do
    $CC $CFLAGS $SHARDFLAGS -fno-jump-tables -I"$ABK_GEN" -c \
      -o "$OUT/obj/abk/$f.o" "$ABK_GEN/$f.c"
    ABK_OBJS+=("$OUT/obj/abk/$f.o")
  done
fi
pids=""
for f in $RT; do
  src="runtime/$f.c"; [ -f "$src" ] || src="runtime/web/$f.c"
  [ -f "$src" ] || continue
  fx=""
  case "$f" in
    dispatch) [ ${#ABK_OBJS[@]} -eq 0 ] || fx="-DNFSU1_HAS_ABK" ;;
    roam_core|roam_game) fx="-ffp-contract=off" ;;
    # These wrappers name NFSU2 guest VAs that collide with unrelated NFSU1
    # functions. Keep their support APIs, but never replace NFSU1 guest code.
    netrace) fx="-Dsub_0053ed20=nfsu2_runtime_sub_0053ed20" ;;
    framerate) fx="-Dsub_0057a0e0=nfsu2_runtime_sub_0057a0e0" ;;
    d3dx_hle) fx="-Dsub_00668cc0=nfsu2_runtime_sub_00668cc0" ;;
  esac
  $CC $CFLAGS $fx -DNFS_ENHANCED=0 -c -o "$OUT/rt/$f.o" "$src" & pids="$pids $!"
done
for f in $WEB; do
  case "$f" in thread_exit) fl="$TARGET $OPT $FEAT $EXTRA" ;; *) fl="$CFLAGS -DNFS_ENHANCED=0" ;; esac
  $CC $fl -c -o "$OUT/rt/web_$f.o" "runtime/web/$f.c" & pids="$pids $!"
done
for p in $pids; do wait "$p" || { echo "runtime compile failed"; exit 1; }; done

# g_fe_mgr is referenced by a FORCESWITCH diagnostic in com.c but not defined
# in the materialized Mac-free snapshot; provide a zero for bring-up linking.
printf '%s\n' 'unsigned int g_fe_mgr;' > "$OUT/rt/nfsu1_link_stubs.c"
$CC $TARGET $OPT -c -o "$OUT/rt/nfsu1_link_stubs.o" "$OUT/rt/nfsu1_link_stubs.c"

# Select objects from this build's sources, rather than linking stale shards,
# stubs or runtime experiments left by a previous output directory.
OBJS=()
if [ ${#ABK_OBJS[@]} -gt 0 ]; then OBJS+=("${ABK_OBJS[@]}"); fi
for src in gen/all/shard_*.c gen/all/fntab.c gen/all/impargs.c gen/all/stubs.c; do
  [ -f "$src" ] && OBJS+=("$OUT/obj/$(basename "$src" .c).o")
done
for f in fntab impargs modinfo; do OBJS+=("$OUT/obj/srv/$f.o"); done
for f in $RT; do
  if [ -f "runtime/$f.c" ] || [ -f "runtime/web/$f.c" ]; then OBJS+=("$OUT/rt/$f.o"); fi
done
for f in $WEB; do OBJS+=("$OUT/rt/web_$f.o"); done
OBJS+=("$OUT/rt/nfsu1_link_stubs.o")
PAGES=$(( INITIAL_MB * 16 ))
# Presets run after the original config loader; the network clock uses real
# time independently of the renderer. The Wasm linker wraps both
# direct calls and function-table references, including calls in the same
# shard. Refuse a build that optimized away a required wrapped call.
for entry in sub_0041c680 sub_00410e50 sub_0066e8b0 sub_004f6360 sub_004f2cb0 sub_0058f090; do
  wrapper_refs=0
  for src in gen/all/shard_*.c; do
    if grep -Fq "$entry(c)" "$src"; then
      obj="$OUT/obj/$(basename "$src" .c).o"
      if ! "$OBJDUMP" -r "$obj" | grep "R_WASM_FUNCTION_INDEX_LEB $entry+" >/dev/null; then
        echo "wrapped $entry call was inlined in $src; rebuild with OPT=-O1" >&2
        exit 1
      fi
      wrapper_refs=$(( wrapper_refs + 1 ))
    fi
  done
  [ "$wrapper_refs" -gt 0 ] || { echo "missing wrapper caller: $entry" >&2; exit 1; }
done
rm -f "$OUT/nfsu1.wasm"
$CC $TARGET $OPT $FEAT $EXTRA -o "$OUT/nfsu1.wasm" "${OBJS[@]}" \
  -Wl,--wrap=sub_0041c680,--wrap=sub_00410e50,--wrap=sub_0066e8b0 \
  -Wl,--wrap=sub_00547db0,--wrap=sub_00547dc0,--wrap=sub_00548610 \
  -Wl,--wrap=sub_00546d70,--wrap=sub_00546e00,--wrap=sub_00547ae0,--wrap=sub_0054e2f0 \
  -Wl,--wrap=sub_0043a220,--wrap=sub_0043a830,--wrap=sub_004390d0 \
  -Wl,--wrap=sub_005647d0,--wrap=sub_004f6360,--wrap=sub_004f2cb0 \
  -Wl,--wrap=sub_0058f090 \
  -Wl,--import-memory,--export-memory,--shared-memory,--max-memory=4294967296 \
  -Wl,--initial-memory=$(( INITIAL_MB * 1048576 )),--global-base=$GUEST_END \
  -Wl,-z,stack-size=$(( 8 * 1048576 )) -Wl,--no-stack-first \
  -lsetjmp -lwasi-emulated-mman -lwasi-emulated-signal -lwasi-emulated-process-clocks \
  2>&1 | { grep -v "^$" || true; } > "$OUT/link.log"
if [ ! -f "$OUT/nfsu1.wasm" ]; then
  echo "link FAILED:"; grep -E "error" "$OUT/link.log" | head -80; exit 1
fi
SIZE=$(wc -c < "$OUT/nfsu1.wasm" | tr -d ' ')
printf '{"pages":%d,"maxPages":65536,"guestEnd":%d,"size":%d,"opt":"%s","lift":"nfsu1-bringup","hdFonts":1}\n' \
  "$PAGES" "$GUEST_END" "$SIZE" "$OPT" > "$OUT/nfsu1.json"
echo "link OK: $OUT/nfsu1.wasm ($(( SIZE / 1048576 )) MB)"
