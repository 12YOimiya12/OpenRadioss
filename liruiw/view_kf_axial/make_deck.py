#!/usr/bin/env python3
"""Generate a multi-element uniaxial-compression deck from the KF LAW99 project.

The reference project ships a single-brick (1 element) uniaxial compression test
in `examples/userlib/kf_law99/test/kf_law99_0000.rad`.  This generator keeps that
setup exactly - same unit cube, same material card, same boundary conditions and
same imposed velocity - and only refines the mesh so the stress/plastic-strain
distribution inside the specimen becomes visible in post-processing.

Reference setup being reproduced (from the project's starter deck):
  geometry    unit cube, x in [0,1], y in [0,1], z in [0,-1]
  material    /MAT/USER02, the KF sample parameter card (verbatim)
  BC          right face (x=1): X translation fixed   (/BCS 100 000)
              left  face (x=0): free, +X imposed velocity 1  (/IMPVEL)
  run         t = 0.002  ->  axial strain = v*t/L = 0.002

Mesh size and output frequency are the constants below.
"""

from pathlib import Path

# ---------------------------------------------------------------- mesh -------
NX, NY, NZ = 10, 4, 4          # bricks along X (load dir), Y, Z  -> 160 elements
LX, LY, LZ = 1.0, 1.0, 1.0     # unit cube, matching the project
DX, DY, DZ = LX / NX, LY / NY, LZ / NZ

T_END = 0.002                  # same total time as the project
OUT_DT = 2.0e-4                # output interval -> 10 frames

# KF material card, copied verbatim from the project's test deck.
KF_CARD = """\
/MAT/USER02/1
KF_LAW99_SAMPLE
             10000.0             10000.0
3.10E10 0.20 1.00E8 1.60 0.75 0.20 0.60 1.00E7
0.04 0.85 0.20 1.0E-6 0.02 0.02
1.05 1.0E7 4.0E8 1.722222222E10 1.722222222E10 0.0 0.0 0.0 5.0E8 8.0E8 1.0E-4
"""


def nid(ix, iy, iz):
    return 1 + ix + (NX + 1) * iy + (NX + 1) * (NY + 1) * iz


def eid(ix, iy, iz):
    return 1 + ix + NX * iy + NX * NY * iz


def gen_nodes():
    # z decreases with iz, matching the project's unit cube (second face at z=-1);
    # the brick node order below is only valid with that handedness.
    out = ["/NODE"]
    for iz in range(NZ + 1):
        for iy in range(NY + 1):
            for ix in range(NX + 1):
                out.append(
                    "%10d%20.8g%20.8g%20.8g"
                    % (nid(ix, iy, iz), ix * DX, iy * DY, -iz * DZ)
                )
    return "\n".join(out)


def gen_bricks():
    # Same node order as the project's single brick (EID + 8 node ids, no part id).
    out = ["/BRICK/1"]
    for iz in range(NZ):
        for iy in range(NY):
            for ix in range(NX):
                n = [
                    nid(ix, iy, iz),
                    nid(ix, iy, iz + 1),
                    nid(ix, iy + 1, iz + 1),
                    nid(ix, iy + 1, iz),
                    nid(ix + 1, iy, iz),
                    nid(ix + 1, iy, iz + 1),
                    nid(ix + 1, iy + 1, iz + 1),
                    nid(ix + 1, iy + 1, iz),
                ]
                out.append("%10d" % eid(ix, iy, iz) + "".join("%10d" % v for v in n))
    return "\n".join(out)


def gen_grnod(gid, title, ids):
    out = ["/GRNOD/NODE/%d" % gid, title]
    for i in range(0, len(ids), 10):
        out.append("".join("%10d" % v for v in ids[i : i + 10]))
    return "\n".join(out)


def face_nodes(ix):
    return [nid(ix, iy, iz) for iz in range(NZ + 1) for iy in range(NY + 1)]


def gen_th():
    # Track a line of elements and nodes through the thickness so the
    # compression wave can be seen advancing from the loaded face.
    ex = [1, NX // 4, NX // 2, 3 * NX // 4, NX]
    out = [
        "/TH/NODE/1",
        "TIME HISTORY OF NODES",
        "#     var1      var2      var3      var4      var5      var6      var7      var8      var9     var10",
        "DEF",
        "#    NODid     Iskew                                           NODname",
    ]
    for k, ix in enumerate([0, NX // 2, NX]):
        out.append("%10d         0%s" % (nid(ix, 0, 0), "NODE-X%d" % ix))
    out += [
        "/TH/BRIC/2",
        "TIME HISTORY OF SOLIDS ELEMENTS",
        "#     var1      var2      var3      var4      var5      var6      var7      var8      var9     var10",
        "DEF",
        "#     Elid                                                      Elname",
    ]
    for e in ex:
        ix = min(e, NX) - 1
        out.append("%10d          %s" % (eid(ix, 0, 0), "ELEM-X%d" % (ix + 1)))
    out += [
        "/TH/PART/3",
        "TIME HISTORY OF PARTS",
        "#     var1      var2      var3      var4      var5      var6      var7      var8      var9     var10",
        "DEF",
        "#     Obj1      Obj2      Obj3      Obj4      Obj5      Obj6      Obj7      Obj8      Obj9     Obj10",
        "         1",
    ]
    return "\n".join(out)


def gen_starter():
    return "\n".join(
        [
            "#RADIOSS STARTER",
            "/BEGIN",
            "LAW99_KF_MULTI",
            "      2022         0",
            "                  kg                  mm                  ms",
            "                  kg                  mm                  ms",
            "/TITLE",
            "LAW99 KF uniaxial compression, multi-element (%dx%dx%d)"
            % (NX, NY, NZ),
            "/IOFLAG",
            "#     IPRI               IGTYP     IOUTP    IOUTYY   IROOTYY     IDROT",
            "         5                   0         0         0         0         0",
            "/ANALY",
            "#    N2D3D             IPARITH      ISUB",
            "         0                   0         0",
            "/DEF_SOLID",
            "#  I_SOLID    ISMSTR             ISTRAIN                                  IFRAME",
            "         0         0                   2                                       0",
            "/SHFRA/V4",
            KF_CARD,
            gen_nodes(),
            # Left face: free (kept from the project deck, so lateral Poisson
            # expansion is unconstrained there).  Right face: X fixed.
            "/BCS/1",
            "BOUNDARY CONDITION LEFT FACE (free)",
            "#  Tra rot   skew_ID  grnod_ID",
            "   000 000         0         1",
            gen_grnod(1, "LEFT FACE", face_nodes(0)),
            "/BCS/2",
            "BOUNDARY CONDITION RIGHT FACE X",
            "#  Tra rot   skew_ID  grnod_ID",
            "   100 000         0         2",
            gen_grnod(2, "RIGHT FACE", face_nodes(NX)),
            "/PART/1",
            "SOLID PID 1",
            "         1         1         0",
            gen_bricks(),
            "/PROP/TYPE14/1",
            "SOLID PID 1",
            "#   Isolid    Ismstr               Icpre               Inpts    Itetra    Iframe                  dn",
            "         0         0                   0                   0         0         0                   0",
            "#                q_a                 q_b                   h            LAMBDA_V                MU_V",
            "             1.0E-20             1.0E-20                  .1                   0                   0",
            "#             dt_min   istrain      IHKT",
            "                   0         0         0",
            "/FUNCT/1",
            "UNIT FUNCTION",
            "#                  X                   Y",
            "                   0                   1",
            "               10000                   1",
            "/IMPVEL/1",
            "Fixed Velocity 1",
            "#funct_IDT       Dir   skew_ID sensor_ID  grnod_ID  frame_ID     Icoor",
            "         1         X         0         0         3         0         0",
            "#           Ascale_x            Fscale_Y              Tstart               Tstop",
            "                   0                   1                   0                   0",
            gen_grnod(3, "LEFT FACE IMPVEL", face_nodes(0)),
            gen_th(),
            "/END",
            "",
        ]
    )


def gen_engine():
    return "\n".join(
        [
            "/ANIM/DT",
            "#   TSTART     TFREQ",
            "0.0 %.6E" % OUT_DT,
            "/ANIM/VECT/DIS",
            "/ANIM/BRICK/TENS/STRESS",
            "/ANIM/ELEM/VONM",
            "/ANIM/ELEM/EPSP",
            "/ANIM/BRICK/DENS",
            "/DT",
            "0.500000 0.000000",
            "/MON/ON",
            "/PARITH/ON",
            "/PRINT/-10/55",
            "/RUN/LAW99_KF_MULTI/1",
            "%.6E" % T_END,
            "/TFILE/4",
            "#            dT_HIS",
            "%.6E" % OUT_DT,
            "# H3D output, including the KF state variables",
            "/H3D/DT",
            "#   TSTART     TFREQ",
            "0.0 %.6E" % OUT_DT,
            "/H3D/SOLID/EPSP",
            "/H3D/SOLID/VONM",
            "/H3D/SOLID/DENS",
            "/H3D/SOLID/TENS/STRESS",
            "/H3D/SOLID/USER/UVAR=1",
            "1",
            "/H3D/SOLID/USER/UVAR=2",
            "1",
            "/H3D/SOLID/USER/UVAR=3",
            "1",
            "/H3D/SOLID/USER/UVAR=4",
            "1",
            "/H3D/SOLID/USER/UVAR=5",
            "1",
            "/H3D/SOLID/USER/UVAR=7",
            "1",
            "/H3D/SOLID/USER/UVAR=8",
            "1",
            "/VERS/2019",
            "",
        ]
    )


def main():
    here = Path(__file__).resolve().parent
    (here / "kf_axial_0000.rad").write_text(gen_starter(), encoding="ascii")
    (here / "kf_axial_0001.rad").write_text(gen_engine(), encoding="ascii")
    print(
        "mesh : %d x %d x %d = %d bricks, %d nodes"
        % (NX, NY, NZ, NX * NY * NZ, (NX + 1) * (NY + 1) * (NZ + 1))
    )
    print("brick: dx=%.4g dy=%.4g dz=%.4g (unit cube)" % (DX, DY, DZ))
    print("load : +X velocity 1 on x=0 face, X fixed on x=1 face, t_end=%.4g" % T_END)
    print("wrote: kf_axial_0000.rad, kf_axial_0001.rad in %s" % here)


if __name__ == "__main__":
    main()
