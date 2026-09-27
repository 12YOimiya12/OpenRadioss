#!/usr/bin/env python3
"""Run the Section 11 KF LAW99 verification checklist.

This script separates automated verification evidence from production
certification gates that require calibrated material data or larger FE
benchmarks.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


LOCAL_RUNTIME = Path(
    r"D:\OpenRadioss\2023-02-04-01-15-23-OpenRadioss-OpenRadioss_win64\OpenRadioss"
)
LOCAL_CMAKE = Path(
    r"D:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
)


@dataclass
class Gate:
    name: str
    status: str
    metrics: dict[str, Any] = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return self.status == "PASS"


def run_command(cmd: list[str], cwd: Path, log_file: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    log_file.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    log_file.write_text(result.stdout, encoding="utf-8", errors="replace")
    return result


def load_validation_module(repo: Path):
    module_path = repo / "examples" / "userlib" / "kf_law99" / "validate_kf_law99.py"
    spec = importlib.util.spec_from_file_location("kf_law99_validation", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load validation module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def kf_poly_pressure(params: list[float], mu_matrix: float, e_int: float = 0.0) -> float:
    k1, k2, k3, gamma = params[18], params[19], params[20], params[21]
    return k1 * mu_matrix + k2 * mu_matrix * mu_matrix + k3 * mu_matrix**3 + gamma * e_int


def kf_pressure_update_python(params: list[float], mu_total: float, alpha_old: float, e_int: float = 0.0) -> tuple[float, float]:
    alpha0 = params[14]
    pcrush = params[15]
    plock = params[16]
    ke = params[17]
    tol = 1.0e-8
    alpha = alpha_old
    if alpha < 1.0 or alpha > alpha0:
        alpha = alpha0

    p_elastic = ke * mu_total
    if p_elastic <= pcrush:
        return p_elastic, alpha

    if alpha <= 1.0 or p_elastic >= plock:
        return kf_poly_pressure(params, mu_total, e_int), 1.0

    denom = plock - pcrush
    for _ in range(40):
        mu_matrix = alpha * (1.0 + mu_total) - 1.0
        pressure = kf_poly_pressure(params, mu_matrix, e_int)
        if pressure >= plock:
            alpha = 1.0
            break
        if denom <= 0.0:
            break

        ratio = (plock - pressure) / denom
        residual = alpha - 1.0 - (alpha0 - 1.0) * ratio * ratio
        if abs(residual) < tol:
            break

        dp_dmu = params[18] + 2.0 * params[19] * mu_matrix + 3.0 * params[20] * mu_matrix * mu_matrix
        dp_dalpha = dp_dmu * (1.0 + mu_total)
        df_dalpha = 1.0 + 2.0 * (alpha0 - 1.0) * ratio * dp_dalpha / denom
        if abs(df_dalpha) < 1.0e-20:
            break
        alpha -= residual / df_dalpha
        alpha = max(1.0, min(alpha, alpha_old))

    mu_matrix = alpha * (1.0 + mu_total) - 1.0
    pressure = kf_poly_pressure(params, mu_matrix, e_int)
    if pressure >= plock:
        alpha = 1.0
        pressure = kf_poly_pressure(params, mu_total, e_int)
    return pressure, alpha


def material_point_matrix(repo: Path, dll: Path, out_dir: Path) -> Gate:
    log = out_dir / "material_point_matrix.log"
    cmd = [
        sys.executable,
        str(repo / "examples" / "userlib" / "kf_law99" / "validate_kf_law99.py"),
        "--dll",
        str(dll),
        "--out",
        str(out_dir / "material_point"),
    ]
    result = run_command(cmd, repo, log)
    result_path = out_dir / "material_point" / "results.json"
    metrics: dict[str, Any] = {"returncode": result.returncode}
    if result_path.exists():
        data = json.loads(result_path.read_text(encoding="utf-8"))
        metrics["checks"] = {item["name"]: item["passed"] for item in data["checks"]}
        metrics["n_checks"] = len(data["checks"])
        metrics["all_passed"] = bool(data["passed"])
    passed = result.returncode == 0 and metrics.get("all_passed") is True
    return Gate("DLL material-point matrix", "PASS" if passed else "FAIL", metrics, [f"log={log}"])


def p_alpha_consistency(repo: Path, dll: Path) -> Gate:
    mod = load_validation_module(repo)
    point = mod.KFLaw99Point(dll)
    records = []
    alpha_old = mod.KF_DEFAULT_PARAMS[14]
    max_rel_error = 0.0
    max_alpha_error = 0.0
    for i in range(24):
        rec = point.step([-0.006, -0.006, -0.006, 0.0, 0.0, 0.0], dt=1.0e-5, case="p_alpha_curve", step_index=i + 1)
        pressure_ref, alpha_ref = kf_pressure_update_python(mod.KF_DEFAULT_PARAMS, rec.mu, alpha_old)
        max_rel_error = max(max_rel_error, abs(rec.pressure - pressure_ref) / max(1.0, abs(pressure_ref)))
        max_alpha_error = max(max_alpha_error, abs(rec.alpha - alpha_ref))
        alpha_old = rec.alpha
        records.append(rec)

    pressures = [r.pressure for r in records]
    js = [r.J for r in records]
    mus = [r.mu for r in records]
    passed = (
        max_rel_error < 1.0e-10
        and max_alpha_error < 1.0e-10
        and all(pressures[i] >= pressures[i - 1] for i in range(1, len(pressures)))
        and all(js[i] <= js[i - 1] for i in range(1, len(js)))
        and all(mus[i] >= mus[i - 1] for i in range(1, len(mus)))
        and records[-1].J < 0.70
        and records[-1].mu > 0.50
    )
    return Gate(
        "P-alpha EOS consistency",
        "PASS" if passed else "FAIL",
        {
            "p_final": records[-1].pressure,
            "J_final": records[-1].J,
            "mu_final": records[-1].mu,
            "alpha_final": records[-1].alpha,
            "max_pressure_rel_error": max_rel_error,
            "max_alpha_abs_error": max_alpha_error,
        },
    )


def step_size_sensitivity(repo: Path, dll: Path) -> Gate:
    mod = load_validation_module(repo)
    final: dict[int, Any] = {}
    for nstep in (16, 32, 64):
        point = mod.KFLaw99Point(dll)
        rec = None
        for i in range(nstep):
            rec = point.step(
                [-0.096 / nstep, 0.0, 0.0, 0.048 / nstep, 0.0, 0.0],
                dt=1.0e-3 / nstep,
                case=f"step_sensitivity_{nstep}",
                step_index=i + 1,
            )
        final[nstep] = rec

    coarse = final[32]
    fine = final[64]
    stress_scale = max(1.0, max(abs(v) for v in fine.stress))
    stress_rel = max(abs(a - b) for a, b in zip(coarse.stress, fine.stress)) / stress_scale
    pressure_rel = abs(coarse.pressure - fine.pressure) / max(1.0, abs(fine.pressure))
    epbar_rel = abs(coarse.epbar - fine.epbar) / max(1.0e-12, abs(fine.epbar))
    damage_rel = abs(coarse.damage - fine.damage) / max(1.0e-12, abs(fine.damage))
    passed = (
        stress_rel < 0.02
        and pressure_rel < 0.01
        and epbar_rel < 0.01
        and damage_rel < 0.03
        and fine.damage >= final[16].damage >= 0.0
        and fine.epbar > 0.0
    )
    return Gate(
        "material-point step-size sensitivity",
        "PASS" if passed else "FAIL",
        {
            "stress_rel_32_vs_64": stress_rel,
            "pressure_rel_32_vs_64": pressure_rel,
            "epbar_rel_32_vs_64": epbar_rel,
            "damage_rel_32_vs_64": damage_rel,
            "damage_16": final[16].damage,
            "damage_32": final[32].damage,
            "damage_64": final[64].damage,
        },
        ["This is a material-point gate, not a mesh-objectivity proof."],
    )


def parse_engine_cycles(text: str) -> int | None:
    match = re.search(r"TOTAL NUMBER OF CYCLES\s*:\s*(\d+)", text)
    return int(match.group(1)) if match else None


def run_fe_one_brick(repo: Path, runtime: Path, dll: Path, out_dir: Path) -> Gate:
    starter = runtime / "exec" / "starter_win64.exe"
    engine = runtime / "exec" / "engine_win64.exe"
    th_to_csv = runtime / "exec" / "th_to_csv_win64.exe"
    if not starter.exists() or not engine.exists():
        return Gate("OpenRadioss one-brick smoke", "FAIL", notes=[f"Runtime executables not found under {runtime}"])

    out_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["RAD_CFG_PATH"] = str(runtime / "hm_cfg_files")
    starter_result = run_command(
        [
            str(starter),
            "-i",
            str(repo / "examples" / "userlib" / "kf_law99" / "test" / "kf_law99_0000.rad"),
            "-dylib",
            str(dll),
        ],
        out_dir,
        out_dir / "starter.log",
        env=env,
    )
    engine_result = run_command(
        [
            str(engine),
            "-i",
            str(repo / "examples" / "userlib" / "kf_law99" / "test" / "kf_law99_0001.rad"),
            "-dylib",
            str(dll),
        ],
        out_dir,
        out_dir / "engine.log",
        env=env,
    )

    starter_text = (out_dir / "starter.log").read_text(encoding="utf-8", errors="replace")
    engine_text = (out_dir / "engine.log").read_text(encoding="utf-8", errors="replace")
    cycles = parse_engine_cycles(engine_text)
    starter_ok = starter_result.returncode == 0 and "0 ERROR(S)" in starter_text
    engine_ok = engine_result.returncode == 0 and "NORMAL TERMINATION" in engine_text and cycles is not None and cycles > 0

    csv_gate = False
    csv_metrics: dict[str, Any] = {}
    t01 = out_dir / "kf_law99T01"
    if th_to_csv.exists() and t01.exists():
        csv_result = run_command([str(th_to_csv), t01.name], out_dir, out_dir / "th_to_csv.log")
        csv_file = out_dir / "kf_law99T01.csv"
        if csv_file.exists():
            with csv_file.open(newline="", encoding="utf-8", errors="replace") as fp:
                rows = list(csv.DictReader(fp))
            numeric_values: list[float] = []
            for row in rows:
                for value in row.values():
                    if value is None or value == "":
                        continue
                    numeric_values.append(float(value))
            csv_gate = (
                len(rows) >= 2
                and all(math.isfinite(v) for v in numeric_values)
                and float(rows[-1]["time"]) > 0.0
                and float(rows[-1]["MASS"]) > 0.0
            )
            csv_metrics = {
                "th_to_csv_returncode": csv_result.returncode,
                "csv_rows": len(rows),
                "csv_columns": len(rows[0]) if rows else 0,
                "final_time": float(rows[-1]["time"]) if rows else 0.0,
                "final_mass": float(rows[-1]["MASS"]) if rows else 0.0,
                "final_internal_energy": float(rows[-1]["INTERNAL ENERGY"]) if rows else 0.0,
            }

    passed = starter_ok and engine_ok and csv_gate
    return Gate(
        "OpenRadioss one-brick smoke and T01 integrity",
        "PASS" if passed else "FAIL",
        {
            "starter_returncode": starter_result.returncode,
            "engine_returncode": engine_result.returncode,
            "cycles": cycles,
            "starter_0_errors": starter_ok,
            "engine_normal_termination": engine_ok,
            **csv_metrics,
        },
        [f"run_dir={out_dir}"],
    )


def build_library(repo: Path, cmake: Path, out_dir: Path) -> Gate:
    if not cmake.exists():
        return Gate("Build KF LAW99 DLL", "FAIL", notes=[f"CMake not found: {cmake}"])
    result = run_command(
        [str(cmake), "--build", str(repo / "build" / "userlib_kf_vs_community"), "--config", "Release"],
        repo,
        out_dir / "build.log",
    )
    dll = repo / "build" / "userlib_kf_vs_community" / "Release" / "libraduser_win64.dll"
    passed = result.returncode == 0 and dll.exists()
    return Gate("Build KF LAW99 DLL", "PASS" if passed else "FAIL", {"returncode": result.returncode, "dll_exists": dll.exists()})


def certification_gates() -> list[Gate]:
    return [
        Gate(
            "rate-effect calibration data gate",
            "NOT_CERTIFIED",
            notes=["Automated rate monotonicity passes, but epsdot0/rateS/rateT are not calibrated to SHPB or other dynamic tests."],
        ),
        Gate(
            "impact benchmark gate",
            "NOT_CERTIFIED",
            notes=["SHPB, plate impact, penetration, and blast benchmarks require calibrated input data and FE benchmark decks."],
        ),
        Gate(
            "mesh-objectivity gate",
            "NOT_CERTIFIED",
            notes=["Damage has no characteristic-length or fracture-energy regularization yet; mesh sensitivity cannot be certified."],
        ),
    ]


def step11_mapping(gates: list[Gate]) -> list[dict[str, str]]:
    gate_map = {g.name: g for g in gates}
    mp = gate_map["DLL material-point matrix"]
    fe = gate_map["OpenRadioss one-brick smoke and T01 integrity"]
    palpha = gate_map["P-alpha EOS consistency"]
    step = gate_map["material-point step-size sensitivity"]
    rate_cert = gate_map["rate-effect calibration data gate"]
    impact = gate_map["impact benchmark gate"]
    mesh = gate_map["mesh-objectivity gate"]
    return [
        {
            "item": "Copy DLL matrix into OpenRadioss FE one-brick matrix",
            "status": "PASS" if mp.passed and fe.passed else "FAIL",
            "evidence": "DLL matrix passed; OpenRadioss one-brick Starter/Engine ran and T01 converted to finite CSV.",
        },
        {
            "item": "Hydrostatic compression: compare P-alpha curve",
            "status": palpha.status,
            "evidence": f"max pressure relative error={palpha.metrics.get('max_pressure_rel_error'):.3e}",
        },
        {
            "item": "Uniaxial compression: pressure strengthening, yield, damage onset",
            "status": "PASS" if mp.metrics.get("checks", {}).get("uniaxial_compression") else "FAIL",
            "evidence": "Covered by DLL material-point matrix.",
        },
        {
            "item": "Uniaxial tension: tensile cutoff and tensile volumetric damage",
            "status": "PASS" if mp.metrics.get("checks", {}).get("uniaxial_tension") else "FAIL",
            "evidence": "Covered by DLL material-point matrix.",
        },
        {
            "item": "Simple shear: radial return and non-negative plastic dissipation",
            "status": "PASS" if mp.metrics.get("checks", {}).get("simple_shear") else "FAIL",
            "evidence": "Covered by DLL material-point matrix.",
        },
        {
            "item": "Rate-effect sweep: monotonicity and calibration readiness",
            "status": "PASS" if mp.metrics.get("checks", {}).get("rate_effect") and mp.metrics.get("checks", {}).get("impact_rate_sweep") else "FAIL",
            "evidence": f"Monotonic checks pass; production calibration status={rate_cert.status}.",
        },
        {
            "item": "Large rotation: corotational objectivity",
            "status": "PASS" if mp.metrics.get("checks", {}).get("corotational_objectivity") else "FAIL",
            "evidence": "DLL objectivity check compares identity and 45-degree rotated shear response.",
        },
        {
            "item": "Impact-rate sweep: SHPB/plate impact/penetration/blast readiness",
            "status": impact.status,
            "evidence": "Material-point impact-rate sweep passes; FE impact benchmarks are not certified without calibrated decks/data.",
        },
        {
            "item": "Mesh sensitivity",
            "status": mesh.status,
            "evidence": "Material-point step-size gate passes; mesh objectivity requires damage regularization and multi-element FE tests.",
        },
        {
            "item": "Time-step sensitivity",
            "status": step.status,
            "evidence": f"32 vs 64 step stress relative difference={step.metrics.get('stress_rel_32_vs_64'):.3e}",
        },
    ]


def write_report(out_dir: Path, gates: list[Gate], mapping: list[dict[str, str]]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    data = {
        "automated_passed": all(g.passed for g in gates if g.status in {"PASS", "FAIL"}),
        "gates": [g.__dict__ for g in gates],
        "section_11_mapping": mapping,
    }
    (out_dir / "step11_results.json").write_text(json.dumps(data, indent=2), encoding="utf-8")

    lines = [
        "# KF LAW99 Section 11 Verification Report",
        "",
        f"Automated gates: {'PASS' if data['automated_passed'] else 'FAIL'}",
        "",
        "## Automated Gates",
        "",
        "| Gate | Status | Key metrics |",
        "|---|---|---|",
    ]
    for gate in gates:
        metrics = ", ".join(f"{k}={v:.6g}" if isinstance(v, float) else f"{k}={v}" for k, v in gate.metrics.items())
        notes = "; ".join(gate.notes)
        text = metrics if metrics else notes
        lines.append(f"| {gate.name} | {gate.status} | {text} |")

    lines.extend(
        [
            "",
            "## Section 11 Mapping",
            "",
            "| Checklist item | Status | Evidence |",
            "|---|---|---|",
        ]
    )
    for item in mapping:
        lines.append(f"| {item['item']} | {item['status']} | {item['evidence']} |")

    lines.extend(
        [
            "",
            "## Scope Boundary",
            "",
            "The PASS gates verify the LAW99 interface, material-point behavior, one-brick solver loading, T01 output integrity, EOS consistency, and material-point time-step sensitivity.",
            "NOT_CERTIFIED items require calibrated experimental data, regularized damage, and FE benchmark decks before production impact use.",
            "",
        ]
    )
    (out_dir / "step11_verification_report.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    repo = Path(__file__).resolve().parents[3]
    parser.add_argument("--repo", type=Path, default=repo)
    parser.add_argument("--runtime", type=Path, default=Path(os.environ.get("OPENRADIOSS_RUNTIME", str(LOCAL_RUNTIME))))
    parser.add_argument("--cmake", type=Path, default=LOCAL_CMAKE)
    parser.add_argument("--dll", type=Path, default=repo / "build" / "userlib_kf_vs_community" / "Release" / "libraduser_win64.dll")
    parser.add_argument("--out", type=Path, default=repo / "build" / "userlib_kf_step11_validation")
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    gates: list[Gate] = []
    if not args.skip_build:
        gates.append(build_library(args.repo, args.cmake, args.out))
    if not args.dll.exists():
        gates.append(Gate("KF DLL availability", "FAIL", notes=[f"DLL not found: {args.dll}"]))
        mapping = step11_mapping(gates + certification_gates()) if len(gates) > 3 else []
        write_report(args.out, gates, mapping)
        return 1

    gates.append(material_point_matrix(args.repo, args.dll, args.out))
    gates.append(p_alpha_consistency(args.repo, args.dll))
    gates.append(step_size_sensitivity(args.repo, args.dll))
    gates.append(run_fe_one_brick(args.repo, args.runtime, args.dll, args.out / "fe_one_brick"))
    gates.extend(certification_gates())

    mapping = step11_mapping(gates)
    write_report(args.out, gates, mapping)

    for gate in gates:
        print(f"{gate.status} {gate.name}")
    print(f"Report: {args.out / 'step11_verification_report.md'}")
    automated_passed = all(g.passed for g in gates if g.status in {"PASS", "FAIL"})
    return 0 if automated_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
