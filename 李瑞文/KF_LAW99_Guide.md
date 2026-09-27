# OpenRadioss KF LAW99 开发指南（初稿）

本文记录当前代码仓库中的 Kong-Fang (KF) 自定义本构实现（v2），基于OpenRadioss-20231226开源版开发。

代码仓库路径如下：

```text
examples/userlib/kf_law99
```

v1版已经跑通 `/MAT/USER02` + LAW99 动态用户库闭环；当前 v2 在这个基础上加入共旋大转动更新、密度/体积驱动 EOS、扩展状态变量和冲击率效应验证。**注意它仍然是没有完整验证的过渡版本**。

## 1. 接口选择

v2沿用已经验证过的 LAW99 动态库路径：

- Starter 入口：`ST_LECM99`
- Engine 入口：`ENG_GET_LAW_USER_VAR`
- 本构更新：`ENG_SIGEPS99`
- 应力写回：`ENG_SET_LAW_USER_VAR`

材料卡使用：

```text
/MAT/USER02
```

OpenRadioss 内部会把 `/MAT/USERxx` 映射到 `ILAW=99`，并把 `xx` 作为用户材料编号传入动态库。

## 2. 模型约定

- 应变：LAW99 传入的增量应变，剪切分量为工程剪切应变。
- 单元：3D solid。
- Voigt 顺序：`[xx, yy, zz, xy, yz, zx]`。
- 剪切应力：张量剪切应力。
- 坐标框架：使用 OpenRadioss 传入的 `R11..R33` 局部基，将旧应力和应变增量旋转到共旋局部框架内更新，再把新应力旋回全局坐标。
- 体积响应：优先使用 `rho/rho0` 得到 `J = rho0/rho` 和 `mu = rho/rho0 - 1`；若密度不可用则使用 `VOLUME`；最后才退回小增量估计。
- OpenRadioss 应力符号：拉为正。
- KF 内部压力符号：压为正，`P = -mean(stress)`。
- 当前偏应力屈服修正：Mises 型径向缩放。
- 当前损伤：标量损伤 `D`，单调非减，值域 `[0, 1]`。

## 3. 参数卡

示例材料卡片段：

```text
/MAT/USER02/1002
KF_LAW99_SAMPLE
             10000.0             10000.0
3.10E10 0.20 1.00E8 1.60 0.75 0.20 0.60 1.00E7
0.04 0.85 0.20 1.0E-6 0.02 0.02
1.05 1.0E7 4.0E8 1.722222222E10 1.722222222E10 0.0 0.0 0.0 5.0E8 8.0E8 1.0E-4
```

第一条数据行固定为 `RHO0 RHOR`，由 Starter 读取。后续三行由用户库解析，顺序为：

1. `E nu fc A N B M T`
2. `D1 D2 beta epsdot0 rateS rateT`
3. `alpha0 Pcrush Plock Ke K1 K2 K3 Gamma Psat Siglim epsf_min`

所有应力、模量、压力、强度参数必须和模型单位系统一致。

## 4. 状态变量

当前 `NUVAR = 8`。OpenRadioss LAW99 的 `UVAR` 按变量分块存储，代码中使用：

```c
UVAR[(ivar - 1) * NEL + i]
```

变量含义：

- `UVAR(1) = D`：损伤。
- `UVAR(2) = alpha`：孔隙/压实变量。
- `UVAR(3) = epbar`：等效塑性应变。
- `UVAR(4) = P`：压为正压力。
- `UVAR(5) = sigma_y`：当前剪切屈服强度。
- `UVAR(6) = epsdot_eq`：等效应变率。
- `UVAR(7) = J`：相对体积，`J = rho0 / rho`。
- `UVAR(8) = mu`：体积压缩量，`mu = rho / rho0 - 1`。

## 5. 本构更新流程

每个积分点的更新顺序：

1. 读取旧应力、应变增量、`D`、`alpha`、`epbar`、密度和体积。
2. 读取 `R11..R33`，校验正交性；若无效则退回全局单位基。
3. 将旧应力和应变增量从全局坐标旋转到共旋局部坐标。
4. 由 `rho/rho0` 或 `VOLUME` 计算 `J` 和 `mu`。
5. 计算压为正压力 `P`，包括弹性孔隙段、压实段和完全压实多项式 EOS。
6. 计算局部偏应力弹性预测。
7. 计算等效应力 `seq`。
8. 计算率效应因子 `DFF`。
9. 计算 KF 最大强度面、残余强度面和损伤插值屈服强度。
10. 若 `seq > sigma_y`，执行径向回归缩放。
11. 用塑性增量和拉伸体积应变增量更新损伤。
12. 将新应力从局部框架旋回全局坐标。
13. 写回新应力、`UVAR`、`SIGY`、`PLA`、`SOUNDSP`、`EINT`。

## 6. 本地编译

```powershell
& "D:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" `
  -S examples/userlib/kf_law99 `
  -B build/userlib_kf_vs_community `
  -G "Visual Studio 17 2022" `
  -A x64 `
  -DCMAKE_GENERATOR_INSTANCE="D:\Program Files\Microsoft Visual Studio\2022\Community"

& "D:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" `
  --build build/userlib_kf_vs_community `
  --config Release
```

生成文件：

```text
build/userlib_kf_vs_community/Release/libraduser_win64.dll
```

## 7. 本地测试

测试命令：

```powershell
$repo = "D:\OpenRadioss\OpenRadioss-latest-20231226"
$runtime = "D:\OpenRadioss\2023-02-04-01-15-23-OpenRadioss-OpenRadioss_win64\OpenRadioss"
$out = Join-Path $repo "build\userlib_kf_runtime_test"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$env:RAD_CFG_PATH = "$runtime\hm_cfg_files"
Set-Location $out

& "$runtime\exec\starter_win64.exe" `
  -i "$repo\examples\userlib\kf_law99\test\kf_law99_0000.rad" `
  -dylib "$repo\build\userlib_kf_vs_community\Release\libraduser_win64.dll"

& "$runtime\exec\engine_win64.exe" `
  -i "$repo\examples\userlib\kf_law99\test\kf_law99_0001.rad" `
  -dylib "$repo\build\userlib_kf_vs_community\Release\libraduser_win64.dll"
```

当前实测结果：

- Starter：`0 ERROR(S)`，有两个旧格式字段 warning，和 J2 示例一致。
- Starter 材料 echo：`Parameter set = input card`，说明 KF 参数已从输入卡读入。
- Engine：`NORMAL TERMINATION`。
- Engine cycle：`TOTAL NUMBER OF CYCLES : 8`。
- 输出目录：`build/userlib_kf_runtime_test`。

### 7.1 本机 MinGW 适配（2026-09，一键脚本）

第 6、7 节记录的是**原开发机**的流程：用 Visual Studio 2022 (MSVC) 编译 DLL，跑预编译的 MSVC 版
OpenRadioss 运行时（`D:\OpenRadioss\2023-02-04-...`）。本机没有 Visual Studio，求解器是仓库自带的
**MinGW gfortran 构建**，所以原命令不能直接用。适配后本项目在本机的运行方式如下。

#### 环境差异

| 项目 | 原开发机（指南第 6/7 节） | 本机（2026-09） |
|---|---|---|
| C 编译器 | MSVC (Visual Studio 2022) | MinGW-w64 gcc 15.2.0 |
| 构建驱动 | `mingw32-make` / MSBuild | **ninja**（`extlib/build_mingw64/bin/ninja.exe`） |
| 求解器可执行文件 | `starter_win64.exe` / `engine_win64.exe` | `starter_win64_gf.exe` / `engine_win64_gf.exe` |
| 求解器位置 | 独立安装目录 | 仓库 `exec/` |
| 配置文件 | 安装目录下 `hm_cfg_files` | 仓库 `hm_cfg_files` |
| 用户库文件名 | `libraduser_win64.dll` | **同为** `libraduser_win64.dll`（源码无 `_gf` 变体） |

用户库 DLL 的**文件名和导出符号在两套工具链下完全相同**，因为
`starter/source/user_interface/dyn_userlib.c` 与 `engine/.../dyn_userlib.c` 里拼的都只是
`libraduser_win64.dll`。所以求解器侧不需要任何改动，适配只发生在“怎么把它编出来、怎么喂给求解器”。

本机 gfortran 求解器**已内置动态用户库支持**（`user_interface/` 被 cmake 无条件编译），
**不需要重新编译求解器**。

#### 一键运行

```bat
run_local_kf.bat
```

在资源管理器双击，或在 `cmd.exe` 里执行即可。**不要从 Git Bash 调用**：Git Bash 会破坏
`G:\...` 形式的 PATH 条目，求解器会静默失败（退出码 3221225785，无输出）。若必须从 Git Bash
触发，用 `cmd //c ".\\run_local_kf.bat"`。

脚本依次做 5 件事，任一步失败即中止：

1. 用 MinGW + ninja 编译 DLL → `build_local/kf_dll/libraduser_win64.dll`；
2. 搭运行时镜像 `build_local/runtime/`（求解器硬链接 + `hm_cfg_files` junction + 编译 `th_to_csv`）；
3. 跑 DLL 材料点矩阵 `validate_kf_law99.py`；
4. 跑第 11 节清单 `run_step11_validation.py`（含单砖 Starter/Engine 和 T01→CSV）；
5. 打印各产物路径。

产物全部落在 `build_local/`，不触碰原 `build/`（原开发机拷来的产物）和仓库根目录。

#### 各步骤的手工等价命令

```bat
rem 0. 环境（cmd.exe）
set "PATH=G:\Postgraduate_Researching\openSource_soft\OpenRadioss\extlib\build_mingw64;G:\x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0\mingw64\bin;%PATH%"
set "RAD_CFG_PATH=G:\Postgraduate_Researching\openSource_soft\OpenRadioss\hm_cfg_files"

rem 1. 编译 DLL（注意是 Ninja，不是 MinGW Makefiles）
cmake -S examples\userlib\kf_law99 -B build_local\kf_dll -G Ninja ^
      -DCMAKE_MAKE_PROGRAM=..\extlib\build_mingw64\bin\ninja.exe -DCMAKE_BUILD_TYPE=Release
cmake --build build_local\kf_dll

rem 2. 材料点矩阵
python examples\userlib\kf_law99\validate_kf_law99.py ^
       --dll build_local\kf_dll\libraduser_win64.dll --out build_local\validation

rem 3. 第 11 节清单
python examples\userlib\kf_law99\run_step11_validation.py ^
       --runtime build_local\runtime --dll build_local\kf_dll\libraduser_win64.dll ^
       --out build_local\step11 --skip-build
```

#### 三个必须知道的坑

1. **用 ninja，不要用 `mingw32-make`。** 本仓库路径含中文（`李瑞文`），`mingw32-make` 会报
   `Illegal byte sequence` 而无法 stat 源文件；`ninja` 能正确处理 UTF-8 路径。主仓库的
   `build_mingw64.sh` 也是因此弃用 make。ninja 就在 `extlib/build_mingw64/bin/ninja.exe`。

2. **`libgcc_s_seh-1.dll` 要拷到 DLL 旁边。** MinGW 编出的用户库依赖这个运行时；
   Python 3.8 以后 `ctypes` 不再用 `PATH` 解析依赖 DLL，所以材料点矩阵会报
   `Could not find module ... (or one of its dependencies)`。`run_local_kf.bat` 会自动把它
   从 MinGW `bin` 拷到 `build_local/kf_dll/`。求解器本身是普通程序，走 `PATH` 即可，不受影响。

3. **`--skip-build` 的原因。** `run_step11_validation.py` 的 `build_library()` 只会构建
   `build/userlib_kf_vs_community`（Visual Studio 工程），本机不存在。DLL 由脚本第 1 步构建，
   所以清单里跳过该门；报告因此不显示 “Build KF LAW99 DLL” 这一行，等价性由脚本第 1 步保证
   （编译失败会立即中止，不会继续跑验证）。

#### 本机运行结果（2026-09-27 实测）

与指南第 7、8、11 节记录的原开发机结果一致：

```text
Step 3  材料点矩阵：8/8 PASS，Overall: PASS
Step 4  第 11 节清单：
        PASS DLL material-point matrix
        PASS P-alpha EOS consistency
        PASS material-point step-size sensitivity
        PASS OpenRadioss one-brick smoke and T01 integrity
        NOT_CERTIFIED rate-effect calibration data gate
        NOT_CERTIFIED impact benchmark gate
        NOT_CERTIFIED mesh-objectivity gate
        （3 项 NOT_CERTIFIED 属预期，与第 11 节说明一致）
```

单砖 FE 日志核对：Starter `0 ERROR(S)` / `2 WARNING(S)`（`/IOFLAG` 与 `/DEF_SOLID` 的旧格式字段
warning，与 J2 示例一致）；Engine `NORMAL TERMINATION` / `TOTAL NUMBER OF CYCLES : 8`；
Starter 材料 echo 打印 `USER MATERIAL LAW99.02 ... Parameter set = input card`，证明动态库已被
求解器加载并读卡；`kf_law99T01.csv` 数值有限、时间步 `2.69E-04` 为正、应力量级正常。

#### 关于 userlib SDK

本项目的 LAW99 用户库是**纯 C 单文件**（只用 libc 头文件、`__declspec(dllexport)`，
不 include 任何 Fortran 侧头文件），因此**不需要** `Tools/userlib_sdk`。SDK 只在编写需要
Fortran 模块（`.mod`）的用户子程序时才用得上。

## 8. 验证矩阵

除 OpenRadioss 单砖 smoke test 外，当前新增了 DLL 级材料点验证脚本：

```text
examples/userlib/kf_law99/validate_kf_law99.py
```

运行命令：

```powershell
python examples/userlib/kf_law99/validate_kf_law99.py
```

该脚本直接调用动态库导出的 LAW99 函数：

```text
ENG_GET_LAW_USER_VAR -> ENG_SIGEPS99 -> ENG_SET_LAW_USER_VAR
```

验证覆盖的情况：

- 静水压缩：压力应为压正、随加载递增，偏应力接近零，`alpha` 不增加。
- 单轴压缩：轴向压应力为负、压正压力为正、损伤单调、屈服强度为正。
- 单轴拉伸：轴向拉应力为正、压力为负、拉伸损伤增加。
- 简单剪切：剪应力为正、产生塑性应变、`DPLA` 非负、损伤单调。
- 大静水压缩：较大体积压缩下 `J < 1`、`mu > 0`、压力持续增加，声速为正。
- 率效应：高应变率下 `epsdot_eq`、`sigma_y` 和剪切响应均高于低应变率。
- 共旋客观性：同一剪切加载在 45 度旋转框架下应力旋转结果一致，标量状态量保持一致。
- 冲击率扫：从低速到高速剪切增量，屈服强度和剪切响应单调增强。

当前结果：

```text
PASS hydrostatic_compression: p_final=9.57784e+08, alpha_initial=1, alpha_final=1, max_seq=0
PASS large_hydrostatic_compression: p_final=5.87038e+09, J_final=0.74579, mu_final=0.340861, alpha_final=1, sound_speed_final=1733.97, max_seq=1.01152e-06
PASS uniaxial_compression: sx_final=-1.358e+09, p_final=8.48132e+08, damage_final=0.0570911, epbar_final=0.0122632, sigma_y_final=7.64802e+08
PASS uniaxial_tension: sx_final=1.45137e+07, p_final=-8.26452e+06, damage_initial=0.00150445, damage_final=0.0955038, epbar_final=7.80945e-05
PASS simple_shear: tau_final=2.51307e+07, epbar_final=0.00234081, damage_final=0.414291, max_dpla=0.00041314
PASS rate_effect: epsdot_low=0.0069282, epsdot_high=6928.2, sigma_y_low=6.24097e+07, sigma_y_high=7.32168e+07, tau_low=3.60323e+07, tau_high=4.22718e+07
PASS corotational_objectivity: max_stress_error=2.98023e-08, stress_scale=3.81445e+07, max_invariant_error=8.04912e-16, rotated_tau_xy_final=0, epbar_final=0.000702158
PASS impact_rate_sweep: epsdot_low=8.66025, epsdot_mid=866.025, epsdot_high=86602.5, sigma_y_low=6.7615e+07, sigma_y_high=7.55362e+07, tau_low=3.90375e+07, tau_high=4.36108e+07
Overall: PASS
```

输出文件：

```text
build/userlib_kf_validation/summary.csv
build/userlib_kf_validation/results.json
build/userlib_kf_validation/validation_report.md
```

注意：该矩阵验证的是本构行为和 LAW99 接口连线，不等于实验标定，也不等于复杂 FE 冲击算例验证。

## 9. 大应变/冲击功能升级计划

当前 v2 已完成大转动和密度 EOS 的第一步升级。

### 9.1 运动学与应力率

- 当前已使用 LAW99 的 `R11..R33` 做共旋大转动更新，并通过 DLL 级旋转客观性检查。
- 下一步若需要真正有限变形，应接入 `ENG_USERLIB_GET_LAW_VAR_2` 中的变形梯度/伸长张量信息，建立基于 Cauchy/Kirchhoff 应力的有限应变框架。
- 明确应力度量：Cauchy 应力、Kirchhoff 应力或 Jaumann/Green-Naghdi 客观率。
- 增加大转动纯弹性测试，验证刚体转动不产生虚假应力。

### 9.2 EOS、能量与冲击一致性

- 当前体积响应已优先改为密度/体积驱动，并写出 `J` 和 `mu`。
- 完整校核 `P-alpha` 压实路径：弹性孔隙段、压实段、完全压实 EOS 段。
- 明确 `EINT` 单位和更新公式，检查冲击下能量守恒。
- 用 Rankine-Hugoniot 或已知冲击压缩数据校核高压 EOS。
- 增加声速和稳定时间步估计的保守更新。

### 9.3 强度、损伤与正则化

- 将当前 Mises 型径向回归扩展到 KF 所需的压力相关强度面和拉剪耦合损伤。
- 明确拉伸截断、残余强度面和高压强度饱和的切换逻辑。
- 加入断裂能或特征长度正则化，避免软化损伤的网格依赖。
- 支持单元删除或极小残余强度策略，并验证质量、能量和接触稳定性。
- 做加载步长敏感性，确认显式大步长下损伤不会数值爆炸。

### 9.4 验证矩阵升级

- DLL 级：当前已有有限旋转客观性检查；继续增加循环加载、卸载、重加载和步长收敛测试。
- FE 单砖：静水压缩、单轴压缩/拉伸、剪切、三轴压缩、率效应。
- FE 多单元：网格敏感性、损伤带宽、能量耗散。
- 冲击基准：平板撞击、SHPB、弹丸侵彻或爆炸载荷基准。
- 输出检查：`D`、`alpha`、`P`、`sigma_y`、`epsdot_eq` 的时程和云图。

### 9.5 工程化与集成

- 将参数解析改成带版本号的材料卡格式，例如 `KF_VERSION 1`。
- 增加参数范围检查和 Starter 端错误信息。
- 建立自动回归脚本：编译 DLL、跑材料点矩阵、跑 OpenRadioss 单砖矩阵。
- 为双精度/单精度分别测试。
- 准备参数标定工作流：静态压缩、拉伸、三轴压缩、SHPB 或冲击数据。

## 10. 当前限制

- 当前是大转动 + 密度 EOS 的 solid 更新，不是完整有限应变乘法塑性。
- 偏应力屈服修正采用 Mises 型径向缩放，尚未实现完整三不变量/拉剪耦合流动势。
- `P-alpha` 压实段是 MVP 牛顿迭代实现，需要用静水压缩数据进一步校核。
- 损伤没有特征长度或断裂能正则化，软化阶段存在网格依赖风险。
- 参数尚未标定，示例值只用于接口和数值闭环测试。

## 11. 后续验证

第 11 节验证现在由脚本自动执行：

```powershell
python examples/userlib/kf_law99/run_step11_validation.py
```

输出文件：

```text
build/userlib_kf_step11_validation/step11_results.json
build/userlib_kf_step11_validation/step11_verification_report.md
```

当前自动验证结果：

```text
PASS Build KF LAW99 DLL
PASS DLL material-point matrix
PASS P-alpha EOS consistency
PASS material-point step-size sensitivity
PASS OpenRadioss one-brick smoke and T01 integrity
NOT_CERTIFIED rate-effect calibration data gate
NOT_CERTIFIED impact benchmark gate
NOT_CERTIFIED mesh-objectivity gate
```

第 11 节条目映射：

- 将 DLL 级验证矩阵复制成 OpenRadioss FE 单砖矩阵：`PASS`。DLL 矩阵通过，OpenRadioss 单砖 Starter/Engine 正常结束，`T01` 可转换为有限 CSV。
- 静水压缩，对比 `P-alpha` 压实曲线：`PASS`。独立 Python 参考公式与 DLL 输出一致，最大压力相对误差为 `0`。
- 单轴压缩，验证压力增强、屈服点和损伤起始：`PASS`，由 DLL 材料点矩阵覆盖。
- 单轴拉伸，验证拉伸截断与拉伸体积损伤项：`PASS`，由 DLL 材料点矩阵覆盖。
- 简单剪切，验证径向回归和非负塑性耗散：`PASS`，由 DLL 材料点矩阵覆盖。
- 率效应扫描：`PASS` 的部分是单调率效应验证；参数标定仍为 `NOT_CERTIFIED`，因为还没有 SHPB 或其他动态实验数据。
- 大转动：`PASS`，DLL 共旋客观性检查比较了原始剪切和 45 度旋转框架响应。
- 冲击率扫描：材料点高率扫描为 `PASS`；SHPB、平板撞击、侵彻或爆炸 FE 基准仍为 `NOT_CERTIFIED`。
- 网格敏感性：材料点步长敏感性为 `PASS`；真正网格客观性仍为 `NOT_CERTIFIED`，因为损伤尚无特征长度或断裂能正则化。
- 时间步敏感性：`PASS`。材料点 32 步与 64 步对比中，应力相对差约 `1.704e-03`，压力相对差约 `7.884e-04`。
