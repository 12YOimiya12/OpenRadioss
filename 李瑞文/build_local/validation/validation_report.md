# KF LAW99 Validation Report

Overall result: PASS

| Check | Result | Key metrics |
|---|---|---|
| hydrostatic_compression | PASS | p_final=9.57784e+08, alpha_initial=1, alpha_final=1, max_seq=0 |
| large_hydrostatic_compression | PASS | p_final=5.87038e+09, J_final=0.74579, mu_final=0.340861, alpha_final=1, sound_speed_final=1733.97, max_seq=1.01152e-06 |
| uniaxial_compression | PASS | sx_final=-1.358e+09, p_final=8.48132e+08, damage_final=0.0570911, epbar_final=0.0122632, sigma_y_final=7.64802e+08 |
| uniaxial_tension | PASS | sx_final=1.45137e+07, p_final=-8.26452e+06, damage_initial=0.00150445, damage_final=0.0955038, epbar_final=7.80945e-05 |
| simple_shear | PASS | tau_final=2.51307e+07, epbar_final=0.00234081, damage_final=0.414291, max_dpla=0.00041314 |
| rate_effect | PASS | epsdot_low=0.0069282, epsdot_high=6928.2, sigma_y_low=6.24097e+07, sigma_y_high=7.32168e+07, tau_low=3.60323e+07, tau_high=4.22718e+07 |
| corotational_objectivity | PASS | max_stress_error=2.98023e-08, stress_scale=3.81445e+07, max_invariant_error=8.04912e-16, rotated_tau_xy_final=0, epbar_final=0.000702158 |
| impact_rate_sweep | PASS | epsdot_low=8.66025, epsdot_mid=866.025, epsdot_high=86602.5, sigma_y_low=6.7615e+07, sigma_y_high=7.55362e+07, tau_low=3.90375e+07, tau_high=4.36108e+07 |

These are DLL-level material-point checks against the exported LAW99 functions. They verify numerical behavior and interface wiring, not calibration against experimental data.
