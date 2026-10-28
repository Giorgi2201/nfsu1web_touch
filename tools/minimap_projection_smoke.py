#!/usr/bin/env python3
"""Check map FVF declarations with active shaders and fixed vertex conversion.

Authored vertices only; this does not execute WGSL or validate game rendering.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, default=ROOT / "work/upstream/nfsu2-web")
    args = parser.parse_args()
    runtime = args.upstream.resolve() / "runtime"
    source = (runtime / "com.c").read_text()
    fetch = source[source.index("static void decl_fetch("):source.index("/* --- DRAWDUMP=")]
    start = source.index("            float pos[4], col[4], uv[4];", source.index("static int draw_up("))
    conversion = source[start:source.index("\n        }\n    }", start)]
    harness = r'''
#include "gfx.h"
#include "vsemu.h"
#include "web/wgsl.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static union { uint8_t bytes[4096]; float floats[1024]; } memory;
static uint8_t *g_mem = memory.bytes;
#define MR8(a) memory.bytes[(a)]
#define MR16(a) (*(uint16_t *)(g_mem + (a)))
#define MR32(a) (*(uint32_t *)(g_mem + (a)))
#define MRF32(a) memory.floats[(a)/4]
#define CH_FLAGS(a) MR32((a)-12)
#define CF_DEVICE 2u
#define IF_VDECL 1
static uint32_t next_address = 256;
static uint32_t gbuf_alloc(uint32_t n) { uint32_t a = next_address; next_address += n; return a; }
static uint32_t com_new(int iface, unsigned n) { (void)iface; return gbuf_alloc(n+16)+16; }
''' + fetch + r'''
static TVert convert(uint32_t g_cur_fvf) {
    uint32_t o = 0, declaration = nfsu1_map_fvf_decl(g_cur_fvf);
    assert(declaration && nfsu1_map_fvf_decl(g_cur_fvf) == declaration);
    uint32_t elements = MR32(declaration + 4);
    int p_off = MR16(elements+2), p_type = MR8(elements+4);
    int c_off = MR16(elements+10), c_type = MR8(elements+12);
    int t_off = MR16(elements+18), t_type = MR8(elements+20);
    /* Author a programmable shader that forwards TEXCOORD0, as the captured
     * map VS does. The old FLOAT2 declaration supplies w=1, failing this. */
    uint32_t tokens[] = {0xfffe0101u, 1u, 0xe00f0000u, 0x90e40002u, 0xffffu};
    VSProg *shader = vs_compile(tokens, sizeof tokens / sizeof tokens[0]);
    assert(shader);
    float inputs[16][4] = {{0}};
    decl_fetch(o + (unsigned)t_off, (unsigned)t_type, inputs[2]);
    VSConst constants = {0}; VSOut output = {0};
    assert(vs_run(shader, &constants, (const float (*)[4])inputs, &output));
    assert(output.tex[0][2] == 0.25f);
    assert(output.tex[0][3] == (g_cur_fvf == 0x20142u ? 0.25f : 1.f));
    int dcl[16][2];
    for (unsigned i = 0; i < 16; i++) { dcl[i][0] = -1; dcl[i][1] = 0; }
    dcl[2][0] = t_off; dcl[2][1] = t_type;
    char translated[32768];
    assert(vs_to_wgsl(shader, 1, (const int (*)[2])dcl, translated, sizeof translated) > 0);
    assert(strstr(translated, "ldf(B + 24u)"));
    if (g_cur_fvf == 0x20142u) assert(strstr(translated, "ldf(B + 28u)"));
    vs_free(shader);
    TVert result = {0}, *out = &result;
''' + conversion + r'''
    return result;
}
int main(void) {
    memory.floats[0] = -0.5f; memory.floats[1] = 0.5f;
    memory.floats[2] = 0.0f;
    memset(memory.bytes + 12, 255, 4);
    /* The projected center of the map: raw UV is far from 0.5,0.5. */
    memory.floats[4] = 0.125f; memory.floats[5] = 0.125f;
    memory.floats[6] = 0.25f; memory.floats[7] = 0.25f;
    for (unsigned mode = 0; mode < 2; mode++) {
        TVert vertex = convert(mode ? 0x20142u : 0x10142u);
        assert(vertex.x == -0.5f && vertex.y == 0.5f && vertex.w == 1.f);
        assert(vertex.r == 1.f && vertex.a == 1.f);
        assert(vertex.t[0][2] == 0.25f);
        assert(vertex.t[0][3] == (mode ? 0.25f : 1.f));
        assert(vertex.t[0][0] / vertex.t[0][mode ? 3 : 2] == 0.5f);
    }
    assert(nfsu1_map_fvf_decl(0x10142u) != nfsu1_map_fvf_decl(0x20142u));
    assert(!nfsu1_map_fvf_decl(0x142u));
    char wgsl[32768];
    assert(wgsl_ff_module(0, wgsl, sizeof wgsl, 0) > 0);
    assert(strstr(wgsl, "textureSample(tex0, smp0, tcoord(i.uv0, P.proj[0]))"));
    assert(strstr(wgsl, "select(select(1.0, q.z, m == 1), q.w, m == 2)"));
    assert(wgsl_ff_module(256, wgsl, sizeof wgsl, 1) > 0);
    assert(strstr(wgsl, "textureSample(tex0, smp0, i.uv0.xyz)"));
    puts("PASS: map FVF declarations preserve q through active CPU/WGSL shaders and fixed vertex conversion");
}
'''
    with tempfile.TemporaryDirectory(prefix="nfsu1-map-") as directory:
        directory = Path(directory)
        c_file, executable = directory / "map.c", directory / "map"
        c_file.write_text(harness)
        subprocess.run(["cc", "-std=c11", "-DVSEMU_WGSL", "-DNFS_ENHANCED=0",
                        "-I", str(runtime), str(c_file), str(runtime / "vsemu.c"),
                        "-lm", "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
