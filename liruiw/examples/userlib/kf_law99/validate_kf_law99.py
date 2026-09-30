#!/usr/bin/env python3
"""Run material-point validation checks against the compiled KF LAW99 DLL.

The script calls the same exported LAW99 functions that OpenRadioss loads:
ENG_GET_LAW_USER_VAR -> ENG_SIGEPS99 -> ENG_SET_LAW_USER_VAR.
"""

from __future__ import annotations

import argparse
import ctypes as ct
import csv
import json
import math
from dataclasses import dataclass, field
from pathlib import Path


KF_DEFAULT_PARAMS = [
    3.10e10, 0.20, 1.00e8, 1.60, 0.75, 0.20, 0.60, 1.00e7,
    0.04, 0.85, 0.20, 1.0e-6, 0.02, 0.02,
    1.05, 1.0e7, 4.0e8, 1.722222222e10, 1.722222222e10,
    0.0, 0.0, 0.0, 5.0e8, 8.0e8, 1.0e-4,
]


def arr(values, ctype=ct.c_double):
    return (ctype * len(values))(*values)


def ptr(value):
    return ct.byref(value)


def deviator(stress):
    mean = sum(stress[:3]) / 3.0
    return [stress[0] - mean, stress[1] - mean, stress[2] - mean, stress[3], stress[4], stress[5]]


def mises(stress):
    s = deviator(stress)
    return math.sqrt(1.5 * (s[0] ** 2 + s[1] ** 2 + s[2] ** 2 + 2.0 * (s[3] ** 2 + s[4] ** 2 + s[5] ** 2)))


def monotone_non_decreasing(values, tol=0.0):
    return all(values[i] + tol >= values[i - 1] for i in range(1, len(values)))


def monotone_non_increasing(values, tol=0.0):
    return all(values[i] <= values[i - 1] + tol for i in range(1, len(values)))


def voigt_to_tensor(v, *, strain=False):
    shear = 0.5 if strain else 1.0
    return [
        [v[0], shear * v[3], shear * v[5]],
        [shear * v[3], v[1], shear * v[4]],
        [shear * v[5], shear * v[4], v[2]],
    ]


def tensor_to_voigt(t, *, strain=False):
    shear = 2.0 if strain else 1.0
    return [
        t[0][0],
        t[1][1],
        t[2][2],
        shear * 0.5 * (t[0][1] + t[1][0]),
        shear * 0.5 * (t[1][2] + t[2][1]),
        shear * 0.5 * (t[0][2] + t[2][0]),
    ]


def rotate_voigt(v, rotation, *, to_local=False, strain=False):
    a = voigt_to_tensor(v, strain=strain)
    b = [[0.0 for _ in range(3)] for _ in range(3)]
    for i in range(3):
        for j in range(3):
            for k in range(3):
                for l in range(3):
                    if to_local:
                        b[i][j] += rotation[k][i] * a[k][l] * rotation[l][j]
                    else:
                        b[i][j] += rotation[i][k] * a[k][l] * rotation[j][l]
    return tensor_to_voigt(b, strain=strain)


def rotation_z(theta):
    c = math.cos(theta)
    s = math.sin(theta)
    return [
        [c, -s, 0.0],
        [s, c, 0.0],
        [0.0, 0.0, 1.0],
    ]


def flatten_rotation(rotation):
    return [rotation[i][j] for i in range(3) for j in range(3)]


def max_abs_diff(a, b):
    return max(abs(x - y) for x, y in zip(a, b))


@dataclass
class StepRecord:
    case: str
    step: int
    deps: list[float]
    stress: list[float]
    pressure: float
    damage: float
    alpha: float
    epbar: float
    sigma_y: float
    epsdot_eq: float
    dpla: float
    J: float
    mu: float
    sound_speed: float


@dataclass
class CheckResult:
    name: str
    passed: bool
    metrics: dict[str, float | str]
    notes: list[str] = field(default_factory=list)


class KFLaw99Point:
    def __init__(self, dll_path: Path, params: list[float] | None = None, rho0: float = 10000.0):
        self.dll_path = dll_path
        self.lib = ct.CDLL(str(dll_path))
        self.params = list(params or KF_DEFAULT_PARAMS)
        self.rho0_value = rho0
        self.nel = ct.c_int(1)
        self.nparam = ct.c_int(len(self.params))
        self.nuvar = ct.c_int(8)
        self.ilaw_user = ct.c_int(2)
        self.nfunc = ct.c_int(0)
        self.ifunc = (ct.c_int * 1)(0)
        self.npf = ct.c_int(0)
        self.ngl = ct.c_int(0)
        self.tf = arr([0.0])
        self.time = ct.c_double(0.0)
        self.up = arr(self.params)
        self.rho0 = arr([self.rho0_value])
        self.rho = arr([self.rho0_value])
        self.volume = arr([1.0])
        self.eint = arr([0.0])
        self.soundsp = arr([0.0])
        self.viscmax = arr([0.0])
        self.uvar = arr([0.0] * self.nuvar.value)
        self.off = arr([1.0])
        self.sigy = arr([0.0])
        self.pla = arr([0.0])
        self.dpla = arr([0.0])
        self.stress_old = [arr([0.0]) for _ in range(6)]
        self.deps = [arr([0.0]) for _ in range(6)]
        self.rotation = [
            arr([1.0]), arr([0.0]), arr([0.0]),
            arr([0.0]), arr([1.0]), arr([0.0]),
            arr([0.0]), arr([0.0]), arr([1.0]),
        ]
        self.stress_new = [arr([0.0]) for _ in range(6)]
        self.sv = [arr([0.0]) for _ in range(6)]
        self.dummy = [arr([0.0]) for _ in range(60)]
        self.jacobian = 1.0
        self._configure_signatures()
        self._connect_law_arrays()

    def _configure_signatures(self):
        pint = ct.POINTER(ct.c_int)
        preal = ct.POINTER(ct.c_double)

        self.lib.ENG_GET_LAW_USER_VAR.argtypes = (
            [pint] * 5
            + [preal] * 9
            + [preal] * 6
            + [preal] * 6
            + [preal] * 6
            + [preal] * 6
            + [preal]
            + [preal] * 6
            + [preal] * 6
        )
        self.lib.ENG_GET_LAW_USER_VAR.restype = None

        self.lib.ENG_SIGEPS99.argtypes = [
            pint, pint, pint, pint, pint, ct.POINTER(ct.c_int), pint,
            preal, preal, preal, preal, preal, preal, preal, pint,
            preal, preal, preal, preal, preal, preal,
        ]
        self.lib.ENG_SIGEPS99.restype = None

        self.lib.ENG_SET_LAW_USER_VAR.argtypes = [preal] * 6 + [preal] * 6 + [preal]
        self.lib.ENG_SET_LAW_USER_VAR.restype = None

    def _connect_law_arrays(self):
        ints = [ct.c_int(0) for _ in range(5)]
        d = self.dummy
        self.lib.ENG_GET_LAW_USER_VAR(
            ptr(ints[0]), ptr(ints[1]), ptr(ints[2]), ptr(ints[3]), ptr(ints[4]),
            self.rotation[0], self.rotation[1], self.rotation[2],
            self.rotation[3], self.rotation[4], self.rotation[5],
            self.rotation[6], self.rotation[7], self.rotation[8],
            self.stress_old[0], self.stress_old[1], self.stress_old[2],
            self.stress_old[3], self.stress_old[4], self.stress_old[5],
            d[9], d[10], d[11], d[12], d[13], d[14],
            d[15], d[16], d[17], d[18], d[19], d[20],
            self.deps[0], self.deps[1], self.deps[2],
            self.deps[3], self.deps[4], self.deps[5],
            self.rho0,
            d[21], d[22], d[23], d[24], d[25], d[26],
            d[27], d[28], d[29], d[30], d[31], d[32],
        )

    def step(self, deps, dt=2.5e-4, case="case", step_index=0, rotation=None):
        for k, value in enumerate(deps):
            self.deps[k][0] = value
        if rotation is not None:
            for k, value in enumerate(flatten_rotation(rotation)):
                self.rotation[k][0] = value

        trace = deps[0] + deps[1] + deps[2]
        self.jacobian *= max(0.05, 1.0 + trace)
        self.rho[0] = self.rho0_value / self.jacobian
        self.volume[0] = self.jacobian

        timestep = ct.c_double(dt)
        self.lib.ENG_SIGEPS99(
            ptr(self.nel), ptr(self.nparam), ptr(self.nuvar), ptr(self.ilaw_user), ptr(self.nfunc),
            self.ifunc, ptr(self.npf), self.tf, ptr(self.time), ptr(timestep),
            self.up, self.rho, self.volume, self.eint, ptr(self.ngl), self.soundsp,
            self.viscmax, self.uvar, self.off, self.sigy, self.pla,
        )
        self.lib.ENG_SET_LAW_USER_VAR(
            self.stress_new[0], self.stress_new[1], self.stress_new[2],
            self.stress_new[3], self.stress_new[4], self.stress_new[5],
            self.sv[0], self.sv[1], self.sv[2], self.sv[3], self.sv[4], self.sv[5],
            self.dpla,
        )

        stress = [self.stress_new[k][0] for k in range(6)]
        for k in range(6):
            self.stress_old[k][0] = stress[k]

        self.time.value += dt
        return StepRecord(
            case=case,
            step=step_index,
            deps=list(deps),
            stress=stress,
            pressure=self.uvar[3],
            damage=self.uvar[0],
            alpha=self.uvar[1],
            epbar=self.uvar[2],
            sigma_y=self.uvar[4],
            epsdot_eq=self.uvar[5],
            dpla=self.dpla[0],
            J=self.uvar[6],
            mu=self.uvar[7],
            sound_speed=self.soundsp[0],
        )


def run_case(name: str, point: KFLaw99Point, increments: list[list[float]], dt: float) -> list[StepRecord]:
    return [point.step(deps, dt=dt, case=name, step_index=i + 1) for i, deps in enumerate(increments)]


def run_case_with_rotation(
    name: str,
    point: KFLaw99Point,
    increments: list[list[float]],
    dt: float,
    rotation,
) -> list[StepRecord]:
    return [
        point.step(deps, dt=dt, case=name, step_index=i + 1, rotation=rotation)
        for i, deps in enumerate(increments)
    ]


def check_hydrostatic(dll: Path) -> tuple[CheckResult, list[StepRecord]]:
    records = run_case("hydrostatic_compression", KFLaw99Point(dll), [[-0.0015, -0.0015, -0.0015, 0, 0, 0]] * 12, 2.5e-4)
    pressures = [r.pressure for r in records]
    alphas = [r.alpha for r in records]
    max_seq = max(mises(r.stress) for r in records)
    max_pressure = max(pressures)
    passed = (
        min(pressures) > 0.0
        and monotone_non_decreasing(pressures, tol=1.0e-6 * max(1.0, max_pressure))
        and monotone_non_increasing(alphas, tol=1.0e-10)
        and max_seq < 1.0e-8 * max(1.0, max_pressure)
    )
    return CheckResult(
        "hydrostatic_compression",
        passed,
        {
            "p_final": pressures[-1],
            "alpha_initial": alphas[0],
            "alpha_final": alphas[-1],
            "max_seq": max_seq,
        },
    ), records


def check_large_hydrostatic_compression(dll: Path) -> tuple[CheckResult, list[StepRecord]]:
    records = run_case(
        "large_hydrostatic_compression",
        KFLaw99Point(dll),
        [[-0.012, -0.012, -0.012, 0, 0, 0]] * 8,
        1.0e-5,
    )
    pressures = [r.pressure for r in records]
    alphas = [r.alpha for r in records]
    js = [r.J for r in records]
    mus = [r.mu for r in records]
    max_seq = max(mises(r.stress) for r in records)
    max_pressure = max(pressures)
    passed = (
        pressures[-1] > pressures[0] > 0.0
        and monotone_non_decreasing(pressures, tol=1.0e-6 * max(1.0, max_pressure))
        and monotone_non_increasing(alphas, tol=1.0e-10)
        and monotone_non_increasing(js, tol=1.0e-12)
        and monotone_non_decreasing(mus, tol=1.0e-12)
        and js[-1] < 0.80
        and mus[-1] > 0.20
        and max_seq < 1.0e-8 * max(1.0, max_pressure)
        and records[-1].sound_speed > 0.0
    )
    return CheckResult(
        "large_hydrostatic_compression",
        passed,
        {
            "p_final": pressures[-1],
            "J_final": js[-1],
            "mu_final": mus[-1],
            "alpha_final": alphas[-1],
            "sound_speed_final": records[-1].sound_speed,
            "max_seq": max_seq,
        },
    ), records


def check_uniaxial_compression(dll: Path) -> tuple[CheckResult, list[StepRecord]]:
    records = run_case("uniaxial_compression", KFLaw99Point(dll), [[-0.003, 0, 0, 0, 0, 0]] * 16, 2.5e-4)
    sx = [r.stress[0] for r in records]
    pressures = [r.pressure for r in records]
    damages = [r.damage for r in records]
    passed = (
        sx[-1] < 0.0
        and pressures[-1] > 0.0
        and all(0.0 <= d <= 1.0 for d in damages)
        and monotone_non_decreasing(damages, tol=1.0e-12)
        and records[-1].sigma_y > 0.0
    )
    return CheckResult(
        "uniaxial_compression",
        passed,
        {
            "sx_final": sx[-1],
            "p_final": pressures[-1],
            "damage_final": damages[-1],
            "epbar_final": records[-1].epbar,
            "sigma_y_final": records[-1].sigma_y,
        },
    ), records


def check_uniaxial_tension(dll: Path) -> tuple[CheckResult, list[StepRecord]]:
    records = run_case("uniaxial_tension", KFLaw99Point(dll), [[0.00004, 0, 0, 0, 0, 0]] * 12, 2.5e-4)
    sx = [r.stress[0] for r in records]
    pressures = [r.pressure for r in records]
    damages = [r.damage for r in records]
    passed = (
        sx[-1] > 0.0
        and pressures[-1] < 0.0
        and damages[-1] > damages[0]
        and monotone_non_decreasing(damages, tol=1.0e-12)
        and all(0.0 <= d <= 1.0 for d in damages)
    )
    return CheckResult(
        "uniaxial_tension",
        passed,
        {
            "sx_final": sx[-1],
            "p_final": pressures[-1],
            "damage_initial": damages[0],
            "damage_final": damages[-1],
            "epbar_final": records[-1].epbar,
        },
    ), records


def check_simple_shear(dll: Path) -> tuple[CheckResult, list[StepRecord]]:
    records = run_case("simple_shear", KFLaw99Point(dll), [[0, 0, 0, 0.0005, 0, 0]] * 12, 2.5e-4)
    tau = [r.stress[3] for r in records]
    dplas = [r.dpla for r in records]
    damages = [r.damage for r in records]
    passed = (
        tau[-1] > 0.0
        and records[-1].epbar > 0.0
        and max(dplas) > 0.0
        and min(dplas) >= -1.0e-14
        and monotone_non_decreasing(damages, tol=1.0e-12)
    )
    return CheckResult(
        "simple_shear",
        passed,
        {
            "tau_final": tau[-1],
            "epbar_final": records[-1].epbar,
            "damage_final": damages[-1],
            "max_dpla": max(dplas),
        },
    ), records


def check_rate_effect(dll: Path) -> tuple[CheckResult, list[StepRecord]]:
    low = KFLaw99Point(dll).step([0, 0, 0, 0.012, 0, 0], dt=1.0, case="rate_effect_low", step_index=1)
    high = KFLaw99Point(dll).step([0, 0, 0, 0.012, 0, 0], dt=1.0e-6, case="rate_effect_high", step_index=1)
    passed = (
        high.epsdot_eq > low.epsdot_eq
        and high.sigma_y > low.sigma_y
        and high.stress[3] > low.stress[3]
    )
    return CheckResult(
        "rate_effect",
        passed,
        {
            "epsdot_low": low.epsdot_eq,
            "epsdot_high": high.epsdot_eq,
            "sigma_y_low": low.sigma_y,
            "sigma_y_high": high.sigma_y,
            "tau_low": low.stress[3],
            "tau_high": high.stress[3],
        },
    ), [low, high]


def check_corotational_objectivity(dll: Path) -> tuple[CheckResult, list[StepRecord]]:
    theta = math.radians(45.0)
    rot = rotation_z(theta)
    local_increments = [[0, 0, 0, 0.0005, 0, 0]] * 8
    global_increments = [rotate_voigt(deps, rot, to_local=False, strain=True) for deps in local_increments]

    base_records = run_case("corotational_identity", KFLaw99Point(dll), local_increments, 2.5e-4)
    rotated_records = run_case_with_rotation("corotational_rot45", KFLaw99Point(dll), global_increments, 2.5e-4, rot)

    stress_errors = []
    invariant_errors = []
    for base, rotated in zip(base_records, rotated_records):
        expected_stress = rotate_voigt(base.stress, rot, to_local=False, strain=False)
        stress_errors.append(max_abs_diff(expected_stress, rotated.stress))
        invariant_errors.append(
            max(
                abs(base.pressure - rotated.pressure),
                abs(base.epbar - rotated.epbar),
                abs(base.damage - rotated.damage),
                abs(base.epsdot_eq - rotated.epsdot_eq),
            )
        )

    stress_scale = max(1.0, max(abs(x) for r in rotated_records for x in r.stress))
    max_stress_error = max(stress_errors)
    max_invariant_error = max(invariant_errors)
    passed = (
        max_stress_error < 1.0e-8 * stress_scale
        and max_invariant_error < 1.0e-10 * max(1.0, rotated_records[-1].pressure, rotated_records[-1].sigma_y)
        and rotated_records[-1].epbar > 0.0
    )
    return CheckResult(
        "corotational_objectivity",
        passed,
        {
            "max_stress_error": max_stress_error,
            "stress_scale": stress_scale,
            "max_invariant_error": max_invariant_error,
            "rotated_tau_xy_final": rotated_records[-1].stress[3],
            "epbar_final": rotated_records[-1].epbar,
        },
    ), base_records + rotated_records


def check_impact_rate_sweep(dll: Path) -> tuple[CheckResult, list[StepRecord]]:
    increments = [0, 0, 0, 0.015, 0, 0]
    dts = [1.0e-3, 1.0e-5, 1.0e-7]
    records = [
        KFLaw99Point(dll).step(increments, dt=dt, case=f"impact_rate_sweep_dt_{dt:g}", step_index=i + 1)
        for i, dt in enumerate(dts)
    ]
    epsdots = [r.epsdot_eq for r in records]
    sigmas = [r.sigma_y for r in records]
    taus = [r.stress[3] for r in records]
    passed = (
        monotone_non_decreasing(epsdots, tol=0.0)
        and monotone_non_decreasing(sigmas, tol=1.0e-8)
        and monotone_non_decreasing(taus, tol=1.0e-8)
        and sigmas[-1] > sigmas[0]
        and taus[-1] > taus[0]
    )
    return CheckResult(
        "impact_rate_sweep",
        passed,
        {
            "epsdot_low": epsdots[0],
            "epsdot_mid": epsdots[1],
            "epsdot_high": epsdots[2],
            "sigma_y_low": sigmas[0],
            "sigma_y_high": sigmas[-1],
            "tau_low": taus[0],
            "tau_high": taus[-1],
        },
    ), records


def write_outputs(out_dir: Path, checks: list[CheckResult], records: list[StepRecord]):
    out_dir.mkdir(parents=True, exist_ok=True)

    with (out_dir / "summary.csv").open("w", newline="", encoding="utf-8") as fp:
        writer = csv.writer(fp)
        writer.writerow(["check", "passed", "metric", "value"])
        for check in checks:
            for key, value in check.metrics.items():
                writer.writerow([check.name, check.passed, key, value])

    with (out_dir / "results.json").open("w", encoding="utf-8") as fp:
        json.dump(
            {
                "passed": all(c.passed for c in checks),
                "checks": [
                    {"name": c.name, "passed": c.passed, "metrics": c.metrics, "notes": c.notes}
                    for c in checks
                ],
                "records": [r.__dict__ for r in records],
            },
            fp,
            indent=2,
        )

    with (out_dir / "validation_report.md").open("w", encoding="utf-8") as fp:
        fp.write("# KF LAW99 Validation Report\n\n")
        fp.write(f"Overall result: {'PASS' if all(c.passed for c in checks) else 'FAIL'}\n\n")
        fp.write("| Check | Result | Key metrics |\n")
        fp.write("|---|---|---|\n")
        for check in checks:
            metrics = ", ".join(f"{k}={v:.6g}" if isinstance(v, float) else f"{k}={v}" for k, v in check.metrics.items())
            fp.write(f"| {check.name} | {'PASS' if check.passed else 'FAIL'} | {metrics} |\n")
        fp.write("\n")
        fp.write("These are DLL-level material-point checks against the exported LAW99 functions. They verify numerical behavior and interface wiring, not calibration against experimental data.\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    root = Path(__file__).resolve().parents[3]
    parser.add_argument(
        "--dll",
        type=Path,
        default=root / "build" / "userlib_kf_vs_community" / "Release" / "libraduser_win64.dll",
        help="Path to compiled KF LAW99 dynamic library.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=root / "build" / "userlib_kf_validation",
        help="Output directory for validation artifacts.",
    )
    args = parser.parse_args()

    if not args.dll.exists():
        raise SystemExit(f"KF user library not found: {args.dll}")

    checks: list[CheckResult] = []
    all_records: list[StepRecord] = []
    for runner in (
        check_hydrostatic,
        check_large_hydrostatic_compression,
        check_uniaxial_compression,
        check_uniaxial_tension,
        check_simple_shear,
        check_rate_effect,
        check_corotational_objectivity,
        check_impact_rate_sweep,
    ):
        check, records = runner(args.dll)
        checks.append(check)
        all_records.extend(records)

    write_outputs(args.out, checks, all_records)

    for check in checks:
        status = "PASS" if check.passed else "FAIL"
        metrics = ", ".join(f"{k}={v:.6g}" if isinstance(v, float) else f"{k}={v}" for k, v in check.metrics.items())
        print(f"{status} {check.name}: {metrics}")

    overall = all(c.passed for c in checks)
    print(f"Overall: {'PASS' if overall else 'FAIL'}")
    print(f"Artifacts: {args.out}")
    return 0 if overall else 1


if __name__ == "__main__":
    raise SystemExit(main())
