#!/usr/bin/env python3
"""Generate the stone-kf (KF concrete) OpenRadioss decks.

Two models are generated from the SAME material card, the SAME boundary
conditions and the SAME imposed velocity - only the mesh differs:

    stone_kf    1 x 1 x 1   =   1 brick     interface / smoke test
    stone_axial 10 x 4 x 4  = 160 bricks    so the stress and damage
                                            distribution is visible

Everything is SI: kg, m, s, Pa.  This is required, not cosmetic - the KF
starter routine derives the pore-collapse threshold as `2750/row0 - 1`, which
is only a sensible number for a density given in kg/m3.

The uniaxial compression setup follows the LAW99 KF reference case that is
already known to run on this machine (liruiw/examples/userlib/kf_law99):
unit cube, right face (x=1) X-fixed, left face (x=0) driven with +X velocity 1,
t_end such that the axial strain is v*t/L.

Mesh and output constants are at the top.  Run:  python make_deck.py
"""

from pathlib import Path

# ---------------------------------------------------------------- mesh -------
MESHES = [
    # (deck stem,        NX, NY, NZ, t_end,  out_dt)
    ("stone_kf",          1,  1,  1, 2.0e-3, 2.0e-4),   #  1 brick, 10 frames
    ("stone_axial",      10,  4,  4, 2.0e-3, 2.0e-4),   # 160 bricks, 10 frames
]
LX, LY, LZ = 1.0, 1.0, 1.0      # unit cube, metres

V_IMPACT = 1.0                  # imposed +X velocity on the loaded face, m/s

RUN_NAME = "STONE_KF"

# ------------------------------------------------------------ material -------
# /MAT/USER01 is read by hm_read_mat_user_99.F, which takes the FIRST data line
# with format (2F20.0) [RHO, RHO_R] and writes the REMAINING lines verbatim into
# SI<root>_0099.scr for LECMUSER01.  LECMUSER01 then reads that scratch file
# with (8F10.0) six times, i.e. 6 lines x 8 fields of width exactly 10.
#
# So both blocks below are FIXED-COLUMN cards and must not be reformatted:
#   density line : 2 fields of width 20
#   parameter    : 6 lines x 8 fields of width 10  ->  cm(1..48)
#
# fc = -3.5E7 Pa is the only field that currently has any effect: LECMUSER01
# takes its absolute value and then rebuilds all 48 parameters from the KF
# empirical formulas for 35 MPa concrete.  The other 47 fields are overwritten,
# so they are written as 0.0.  See Stone_mode二次开发步骤.md.
FC = -3.5e7                     # Pa; negative sign is the file's own convention


def _field(v, width):
    """Right-justify one value into a fixed-width field of a fixed-format card."""
    s = ("%g" % v).upper()      # Fortran accepts e/E, but E is the convention here
    assert len(s) <= width, "value %r does not fit in a %d-wide field" % (s, width)
    return s.rjust(width)


def _f20(v):
    """One field of a (2F20.0) density line."""
    return _field(v, 20)


def _f10(v):
    """One field of an (8F10.0) parameter line."""
    return _field(v, 10)


def gen_mat_card():
    cm = [0.0] * 48
    cm[0] = FC
    lines = [
        "/MAT/USER01/1",
        "STONE KF CONCRETE",
        "#                 RHO                RHO_R",
        _f20(2500.0) + _f20(2500.0),
        "#   fc (Pa)  -- remaining 47 fields are recomputed by LECMUSER01 --",
    ]
    for row in range(6):
        lines.append("".join(_f10(v) for v in cm[8 * row : 8 * row + 8]))
    return "\n".join(lines)


# ------------------------------------------------------------------ mesh -----
def make_ids(NX, NY, NZ):
    def nid(ix, iy, iz):
        return 1 + ix + (NX + 1) * iy + (NX + 1) * (NY + 1) * iz

    def eid(ix, iy, iz):
        return 1 + ix + NX * iy + NX * NY * iz

    return nid, eid


def gen_nodes(NX, NY, NZ):
    nid, _ = make_ids(NX, NY, NZ)
    DX, DY, DZ = LX / NX, LY / NY, LZ / NZ
    out = ["/NODE"]
    # z decreases with iz (second face at z = -LZ); the brick node order below
    # is only valid with that handedness.
    for iz in range(NZ + 1):
        for iy in range(NY + 1):
            for ix in range(NX + 1):
                out.append(
                    "%10d%20.8g%20.8g%20.8g"
                    % (nid(ix, iy, iz), ix * DX, iy * DY, -iz * DZ)
                )
    return "\n".join(out)


def gen_bricks(NX, NY, NZ):
    nid, eid = make_ids(NX, NY, NZ)
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


def face_nodes(NX, NY, NZ, ix):
    nid, _ = make_ids(NX, NY, NZ)
    return [nid(ix, iy, iz) for iz in range(NZ + 1) for iy in range(NY + 1)]


def gen_th(NX, NY, NZ):
    """Track a few nodes/elements through the thickness so the compression wave
    can be seen advancing from the loaded face."""
    nid, eid = make_ids(NX, NY, NZ)

    node_x = sorted({0, NX // 2, NX})
    elem_x = sorted({max(0, min(NX - 1, e - 1)) for e in
                     {1, NX // 4, NX // 2, 3 * NX // 4, NX}})

    out = [
        "/TH/NODE/1",
        "TIME HISTORY OF NODES",
        "#     var1      var2      var3      var4      var5      var6      var7      var8      var9     var10",
        "DEF",
        "#    NODid     Iskew                                           NODname",
    ]
    for ix in node_x:
        out.append("%10d         0%s" % (nid(ix, 0, 0), "NODE-X%d" % ix))
    out += [
        "/TH/BRIC/2",
        "TIME HISTORY OF SOLIDS ELEMENTS",
        "#     var1      var2      var3      var4      var5      var6      var7      var8      var9     var10",
        # Explicit variable list instead of DEF.  Channel numbers are documented
        # in engine/source/output/th/thsol.F: 2=SX 3=SY 4=SZ 8=IE 9=DENS
        # 11=VOL 12=PLAS.  PLAS is channel 12 and is NOT in the DEF set, so it
        # has to be asked for by name to see LUSER01's damage variable.
        "%10s%10s%10s%10s%10s%10s" % ("SX", "SY", "SZ", "PLAS", "DENS", "VOL"),
        "#     Elid                                                      Elname",
    ]
    for ix in elem_x:
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


def gen_starter(NX, NY, NZ):
    return "\n".join(
        [
            "#RADIOSS STARTER",
            "/BEGIN",
            RUN_NAME,
            "      2022         0",
            # SI units, unlike the LAW99 KF reference case (kg/mm/ms).
            "                  kg                   m                   s",
            "                  kg                   m                   s",
            "/TITLE",
            "STONE KF concrete uniaxial compression (%dx%dx%d)" % (NX, NY, NZ),
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
            gen_mat_card(),
            gen_nodes(NX, NY, NZ),
            # Left face (x=0): free, so lateral Poisson expansion is
            # unconstrained there.  Right face (x=1): X translation fixed.
            "/BCS/1",
            "BOUNDARY CONDITION LEFT FACE (free)",
            "#  Tra rot   skew_ID  grnod_ID",
            "   000 000         0         1",
            gen_grnod(1, "LEFT FACE", face_nodes(NX, NY, NZ, 0)),
            "/BCS/2",
            "BOUNDARY CONDITION RIGHT FACE X",
            "#  Tra rot   skew_ID  grnod_ID",
            "   100 000         0         2",
            gen_grnod(2, "RIGHT FACE", face_nodes(NX, NY, NZ, NX)),
            "/PART/1",
            "SOLID PID 1",
            "         1         1         0",
            gen_bricks(NX, NY, NZ),
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
            _f20(0.0) + _f20(1.0),
            _f20(1.0e9) + _f20(1.0),
            "/IMPVEL/1",
            "Fixed Velocity 1",
            "#funct_IDT       Dir   skew_ID sensor_ID  grnod_ID  frame_ID     Icoor",
            "         1         X         0         0         3         0         0",
            "#           Ascale_x            Fscale_Y              Tstart               Tstop",
            # Taken verbatim from the LAW99 KF deck that is known to run on
            # this machine: Ascale_x=0 with the unit function gives a constant
            # imposed velocity of Fscale_Y = V_IMPACT m/s.
            _f20(0.0) + _f20(V_IMPACT) + _f20(0.0) + _f20(0.0),
            gen_grnod(3, "LEFT FACE IMPVEL", face_nodes(NX, NY, NZ, 0)),
            gen_th(NX, NY, NZ),
            "/END",
            "",
        ]
    )


def gen_engine(t_end, out_dt):
    return "\n".join(
        [
            "/ANIM/DT",
            "#   TSTART     TFREQ",
            "0.0 %.6E" % out_dt,
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
            "/RUN/%s/1" % RUN_NAME,
            "%.6E" % t_end,
            "/TFILE/4",
            "#            dT_HIS",
            "%.6E" % out_dt,
            # H3D carries the KF state variables (LUSER01's uvar), which the
            # RADIOSS animation files do not.  Needs RAD_H3D_PATH to point at
            # extlib/h3d/lib/win64.  Note: the format is v24, so a recent
            # HyperWorks is required to read it (HW14 cannot).
            "/H3D/DT",
            "#   TSTART     TFREQ",
            "0.0 %.6E" % out_dt,
            "/H3D/SOLID/EPSP",
            "/H3D/SOLID/VONM",
            "/H3D/SOLID/DENS",
            "/H3D/SOLID/TENS/STRESS",
            "/H3D/SOLID/USER/UVAR=5",
            "1",
            "/H3D/SOLID/USER/UVAR=9",
            "1",
            "/H3D/SOLID/USER/UVAR=10",
            "1",
            "/H3D/SOLID/USER/UVAR=12",
            "1",
            "/VERS/2019",
            "",
        ]
    )


def main():
    here = Path(__file__).resolve().parent
    deck = here / "deck"
    deck.mkdir(exist_ok=True)

    for stem, NX, NY, NZ, t_end, out_dt in MESHES:
        (deck / ("%s_0000.rad" % stem)).write_text(gen_starter(NX, NY, NZ), encoding="ascii")
        (deck / ("%s_0001.rad" % stem)).write_text(gen_engine(t_end, out_dt), encoding="ascii")
        print(
            "%-12s  %2d x %2d x %2d = %4d bricks, %5d nodes, t_end=%g, %d frames,"
            " axial strain %g"
            % (stem, NX, NY, NZ, NX * NY * NZ,
               (NX + 1) * (NY + 1) * (NZ + 1), t_end, round(t_end / out_dt),
               V_IMPACT * t_end / LX)
        )
    print("wrote to %s" % deck)


if __name__ == "__main__":
    main()
