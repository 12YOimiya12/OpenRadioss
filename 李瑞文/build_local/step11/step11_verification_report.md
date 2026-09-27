# KF LAW99 Section 11 Verification Report

Automated gates: PASS

## Automated Gates

| Gate | Status | Key metrics |
|---|---|---|
| DLL material-point matrix | PASS | returncode=0, checks={'hydrostatic_compression': True, 'large_hydrostatic_compression': True, 'uniaxial_compression': True, 'uniaxial_tension': True, 'simple_shear': True, 'rate_effect': True, 'corotational_objectivity': True, 'impact_rate_sweep': True}, n_checks=8, all_passed=True |
| P-alpha EOS consistency | PASS | p_final=9.41037e+09, J_final=0.64666, mu_final=0.546409, alpha_final=1, max_pressure_rel_error=0, max_alpha_abs_error=0 |
| material-point step-size sensitivity | PASS | stress_rel_32_vs_64=0.00170406, pressure_rel_32_vs_64=0.000788406, epbar_rel_32_vs_64=0.00185081, damage_rel_32_vs_64=0.016133, damage_16=0.174168, damage_32=0.179684, damage_64=0.18263 |
| OpenRadioss one-brick smoke and T01 integrity | PASS | starter_returncode=0, engine_returncode=0, cycles=8, starter_0_errors=True, engine_normal_termination=True, th_to_csv_returncode=0, csv_rows=4, csv_columns=55, final_time=0.00161563, final_mass=10000, final_internal_energy=40592 |
| rate-effect calibration data gate | NOT_CERTIFIED | Automated rate monotonicity passes, but epsdot0/rateS/rateT are not calibrated to SHPB or other dynamic tests. |
| impact benchmark gate | NOT_CERTIFIED | SHPB, plate impact, penetration, and blast benchmarks require calibrated input data and FE benchmark decks. |
| mesh-objectivity gate | NOT_CERTIFIED | Damage has no characteristic-length or fracture-energy regularization yet; mesh sensitivity cannot be certified. |

## Section 11 Mapping

| Checklist item | Status | Evidence |
|---|---|---|
| Copy DLL matrix into OpenRadioss FE one-brick matrix | PASS | DLL matrix passed; OpenRadioss one-brick Starter/Engine ran and T01 converted to finite CSV. |
| Hydrostatic compression: compare P-alpha curve | PASS | max pressure relative error=0.000e+00 |
| Uniaxial compression: pressure strengthening, yield, damage onset | PASS | Covered by DLL material-point matrix. |
| Uniaxial tension: tensile cutoff and tensile volumetric damage | PASS | Covered by DLL material-point matrix. |
| Simple shear: radial return and non-negative plastic dissipation | PASS | Covered by DLL material-point matrix. |
| Rate-effect sweep: monotonicity and calibration readiness | PASS | Monotonic checks pass; production calibration status=NOT_CERTIFIED. |
| Large rotation: corotational objectivity | PASS | DLL objectivity check compares identity and 45-degree rotated shear response. |
| Impact-rate sweep: SHPB/plate impact/penetration/blast readiness | NOT_CERTIFIED | Material-point impact-rate sweep passes; FE impact benchmarks are not certified without calibrated decks/data. |
| Mesh sensitivity | NOT_CERTIFIED | Material-point step-size gate passes; mesh objectivity requires damage regularization and multi-element FE tests. |
| Time-step sensitivity | PASS | 32 vs 64 step stress relative difference=1.704e-03 |

## Scope Boundary

The PASS gates verify the LAW99 interface, material-point behavior, one-brick solver loading, T01 output integrity, EOS consistency, and material-point time-step sensitivity.
NOT_CERTIFIED items require calibrated experimental data, regularized damage, and FE benchmark decks before production impact use.
