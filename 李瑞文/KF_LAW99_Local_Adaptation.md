# KF LAW99 本机 MinGW 适配说明

本文记录如何把李瑞文的 KF LAW99 二次开发项目从**原开发机（Visual Studio 2022 / MSVC）**
迁移到**本机（MinGW gfortran）**上跑通。

- 适用范围：`examples/userlib/kf_law99/`（v2 版本，即当前主开发分支）
- 适配日期：2026-09-27
- 一键入口：`run_local_kf.bat`
- 项目原理与验证矩阵本身的说明，见同目录 `KF_LAW99_Guide.md`；本文只讲**本机怎么跑起来**。

---

## 1. 为什么需要适配

`KF_LAW99_Guide.md` 第 6、7 节记录的是**原开发机**的流程，硬编码了那台机器的路径：

| 原开发机 | 路径 |
|---|---|
| 源码仓库 | `D:\OpenRadioss\OpenRadioss-latest-20231226` |
| 求解器运行时 | `D:\OpenRadioss\2023-02-04-01-15-23-OpenRadioss-OpenRadioss_win64\OpenRadioss` |
| CMake | `D:\Program Files\Microsoft Visual Studio\2022\Community\...\cmake.exe` |
| 编译器 | MSVC（Visual Studio 2022） |
| 求解器可执行文件 | `starter_win64.exe` / `engine_win64.exe` |

本机这些都不存在：**没有安装 Visual Studio**，求解器是仓库自带的 **MinGW gfortran 构建**。
所以原命令直接跑不通，需要适配。

---

## 2. 环境对照

| 项目 | 原开发机（MSVC） | 本机（MinGW gfortran） |
|---|---|---|
| C 编译器 | MSVC (VS 2022) | MinGW-w64 gcc 15.2.0 |
| 构建驱动 | MSBuild / mingw32-make | **ninja**（`extlib/build_mingw64/bin/ninja.exe`） |
| CMake | VS2022 自带的 `cmake.exe` | `G:\Program Files\CMake\bin`（4.2.3） |
| 求解器可执行文件 | `starter_win64.exe` / `engine_win64.exe` | `starter_win64_gf.exe` / `engine_win64_gf.exe` |
| 求解器位置 | 独立安装目录 | 仓库根 `exec/` |
| 配置文件 `hm_cfg_files` | 安装目录下 | 仓库根 |
| 用户库 DLL 文件名 | `libraduser_win64.dll` | **同为** `libraduser_win64.dll` |
| Python | 3.12 | 3.14.2 |

---

## 3. 关键结论：为什么需要的改动这么小

适配前先读了求解器源码，确认了三件事，因此**不需要重新编译求解器**，
也**不需要改动任何项目源码**：

1. **本机求解器已内置动态用户库支持。**
   `starter/CMakeLists.txt` 用 `file(GLOB_RECURSE ...)` 无条件编译 `source/` 下的全部文件，
   其中包含 `user_interface/`。本机的 `build_mingw64_starter/build.ninja` 里确实有
   `dyn_userlib.c.obj`。所以 gfortran 版求解器本来就能加载用户库。

2. **用户库的 DLL 文件名两套工具链下完全一样。**
   `starter/source/user_interface/dyn_userlib.c` 与 `engine/source/user_interface/dyn_userlib.c`
   里拼接的名字只有 `libraduser_win64.dll`（单精度为 `libraduser_win64_sp.dll`），
   **源码中不存在 `_gf` 变体**。所以虽然求解器可执行文件名多了 `_gf` 后缀，
   用户库这边**不用改名**。

3. **DLL 源码是纯 C，不依赖 Fortran SDK。**
   `raduser_kf_law99.c` 只 include 了 libc 头文件，用 `__declspec(dllexport)` 导出
   `ST_LECM99` / `ENG_SIGEPS99` / `ENG_GET_LAW_USER_VAR` / `ENG_SET_LAW_USER_VAR` 等符号，
   不涉及任何 Fortran 模块（`.mod`）。因此**不需要 `Tools/userlib_sdk`**，
   MinGW gcc 直接就能编。SDK 只在编写需要 Fortran 侧头的用户子程序时才用得上。

另外 deck 侧也不用改：`/MAT/USER02` → `ILAW=99` 的映射由标准 reader 完成
（`starter/source/materials/mat/hm_read_mat.F90` 里把 `USER01..USER24` 分发到用户材料读取），
测试卡 `test/kf_law99_0000.rad`、`0001.rad` 里也没有 `/H3D` 之类本机缺失的块。

---

## 4. 改动范围

**新增（本机适配的全部内容）：**

| 文件 | 作用 |
|---|---|
| `run_local_kf.bat` | 一键脚本：编译 DLL → 搭运行时镜像 → 跑材料点矩阵 → 跑第 11 节清单 |
| `KF_LAW99_Local_Adaptation.md` | 本文 |

**未改动（刻意保持原样）：**

- `examples/userlib/kf_law99/raduser_kf_law99.c`（本构实现）
- `examples/userlib/kf_law99/CMakeLists.txt`
- `examples/userlib/kf_law99/validate_kf_law99.py`（材料点矩阵）
- `examples/userlib/kf_law99/run_step11_validation.py`（第 11 节清单）
- `examples/userlib/kf_law99/test/*.rad`、`example_mat_user02.rad`（测试卡）
- 原 `build/`（原开发机拷来的 MSVC 产物）
- 仓库根 `exec/`、`hm_cfg_files/`（不写入任何新文件）

两个 Python 脚本里虽然硬编码了 `D:\...` 路径，但都提供了命令行参数
（`--repo` / `--runtime` / `--cmake` / `--dll` / `--out` / `--skip-build`），
所以可以用参数覆盖，不必改源码。

---

## 5. 一键运行

```bat
run_local_kf.bat
```

- 在**资源管理器双击**，或在 `cmd.exe` 里执行。
- 脚本结束时**会暂停**（`请按任意键继续...`），否则双击时新开的 cmd 窗口会立即关闭、看不到汇总。
- 双击或从其他脚本调用时若要跳过暂停、直接返回，加参数：`run_local_kf.bat nopause`
- **不要从 Git Bash 调用。** Git Bash 会把加到 PATH 里的 `G:\...` 条目改坏，
  求解器加载不到 MinGW 运行时 DLL，会静默失败（退出码 3221225785，无输出）。
  若确实要从 Git Bash 触发，用 `cmd //c ".\\run_local_kf.bat"`。

脚本依次执行 5 步，任一步失败即中止并返回非零退出码：

| 步骤 | 内容 |
|---|---|
| 1/5 | 用 MinGW + ninja 编译用户库 → `build_local/kf_dll/libraduser_win64.dll` |
| 2/5 | 搭运行时镜像 `build_local/runtime/`（求解器硬链接 + `hm_cfg_files` junction + 编译 `th_to_csv`） |
| 3/5 | 跑 DLL 材料点矩阵 `validate_kf_law99.py` |
| 4/5 | 跑第 11 节清单 `run_step11_validation.py`（含单砖 Starter/Engine 和 T01→CSV） |
| 5/5 | 打印各产物路径 |

所有产物落在 `build_local/`，不污染原 `build/` 和仓库根目录。

---

## 6. 手工等价命令

如果想逐步执行、或排查某一步，以下是脚本内部实际用的命令（在 `cmd.exe` 中、`李瑞文/` 目录下）：

```bat
rem 0. 环境：MinGW 运行时 + extlib(ninja/hm_reader) 入 PATH，并设置配置文件目录
set "PATH=G:\Postgraduate_Researching\openSource_soft\OpenRadioss\extlib\build_mingw64;G:\x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0\mingw64\bin;%PATH%"
set "RAD_CFG_PATH=G:\Postgraduate_Researching\openSource_soft\OpenRadioss\hm_cfg_files"

rem 1. 编译 DLL（注意是 Ninja，不是 MinGW Makefiles）
cmake -S examples\userlib\kf_law99 -B build_local\kf_dll -G Ninja ^
      -DCMAKE_MAKE_PROGRAM=..\extlib\build_mingw64\bin\ninja.exe -DCMAKE_BUILD_TYPE=Release
cmake --build build_local\kf_dll
copy /y "G:\x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0\mingw64\bin\libgcc_s_seh-1.dll" build_local\kf_dll\

rem 2. 材料点矩阵（8 项检查）
python examples\userlib\kf_law99\validate_kf_law99.py ^
       --dll build_local\kf_dll\libraduser_win64.dll --out build_local\validation

rem 3. 第 11 节清单（含单砖 FE 求解）
python examples\userlib\kf_law99\run_step11_validation.py ^
       --runtime build_local\runtime --dll build_local\kf_dll\libraduser_win64.dll ^
       --out build_local\step11 --skip-build
```

单独手动跑求解器（第 2 步搭好镜像后）：

```bat
build_local\runtime\exec\starter_win64.exe -i examples\userlib\kf_law99\test\kf_law99_0000.rad -dylib build_local\kf_dll\libraduser_win64.dll
build_local\runtime\exec\engine_win64.exe  -i examples\userlib\kf_law99\test\kf_law99_0001.rad -dylib build_local\kf_dll\libraduser_win64.dll
```

---

## 7. 运行时镜像目录是干什么的

`run_step11_validation.py` 内部把求解器可执行文件名写死为 `starter_win64.exe` /
`engine_win64.exe`，并且从 `--runtime` 指向的目录下去找 `exec/`、`hm_cfg_files/`。
本机求解器实际叫 `*_gf.exe`，且 `exec/` 里**没有** `th_to_csv`。

所以脚本第 2 步构造了一个 `build_local/runtime/`，模拟原开发机的运行时目录布局：

```text
build_local/runtime/
├── exec/
│   ├── starter_win64.exe      ← 硬链接到 ..\..\exec\starter_win64_gf.exe
│   ├── engine_win64.exe       ← 硬链接到 ..\..\exec\engine_win64_gf.exe
│   └── th_to_csv_win64.exe    ← 用 gcc 现场编译（源码在 Tools 仓库）
└── hm_cfg_files               ← junction（目录联接）到仓库根的 hm_cfg_files
```

- 用**硬链接**而非拷贝：两个求解器共约 60 MB，硬链接零额外占用，且与源文件同一份数据。
- 用 **junction** 而非拷贝：`hm_cfg_files` 有 37 MB，且是只读配置，没必要复制。
- `th_to_csv` 源码不在 OpenRadioss 仓库里（仓库内的 `tools/th_to_csv/` 只有 README），
  在 `G:\Postgraduate_Researching\openSource_soft\Tools\output_converters\th_to_csv\src\th_to_csv.c`，
  是单文件 C 程序，`gcc -O2` 一条命令即可编出。

---

## 8. 四个必须知道的坑

### 8.1 用 ninja，不要用 `mingw32-make`

本仓库路径含中文（`李瑞文`），`mingw32-make` 在 stat 源文件时会直接报
`Illegal byte sequence` 而无法编译；`ninja` 能正确处理 UTF-8 路径。
主仓库的 `build_mingw64.sh` 也弃用了 make（那里的原因是 jobserver 崩溃，但结论一样）。
ninja 就在 `extlib/build_mingw64/bin/ninja.exe`，通过
`-G Ninja -DCMAKE_MAKE_PROGRAM=<ninja路径>` 指定。

### 8.2 `libgcc_s_seh-1.dll` 必须放到用户库 DLL 旁边

MinGW 编出的用户库依赖 `libgcc_s_seh-1.dll`。**Python 3.8 以后 `ctypes` 不再通过 PATH
解析依赖 DLL**，所以即使 PATH 里有 MinGW 的 `bin`，材料点矩阵仍会报：

```text
FileNotFoundError: Could not find module '...\libraduser_win64.dll' (or one of its dependencies).
```

把 `libgcc_s_seh-1.dll` 拷到 `libraduser_win64.dll` 同一目录即可解决（加载器会先搜 DLL 自身目录）。
`run_local_kf.bat` 自动完成这一步。

求解器是普通可执行程序、走常规 PATH 解析，**不受此影响**——所以只有 Python/ctypes 这条路需要处理。

### 8.3 `--skip-build` 的原因

`run_step11_validation.py` 的 `build_library()` 只会去构建
`build/userlib_kf_vs_community`（一个 Visual Studio 工程目录），本机不存在。
DLL 已经由脚本第 1 步建好，所以用 `--skip-build` 跳过该门。

副作用：报告里不会出现 `Build KF LAW99 DLL` 这一行。等价性由脚本第 1 步保证——
编译失败会立即中止，不会继续往下跑。若要报告里也有这一行，可自行执行一次
`cmake --build` 并把结果写进报告。

### 8.4 不要从 Git Bash 启动求解器

见第 5 节。症状识别：**退出码 3221225785（0xC0000142）且输出为空**，
说明是 PATH/动态库问题，不是 deck 写错了。

---

## 9. 产物位置速查

全部相对 `李瑞文/`：

| 内容 | 路径 |
|---|---|
| 编好的用户库 DLL（含 `libgcc_s_seh-1.dll`） | `build_local/kf_dll/` |
| **材料点矩阵报告**（8 项检查） | `build_local/validation/validation_report.md` |
| 材料点原始数据 | `build_local/validation/results.json`、`summary.csv` |
| **第 11 节总报告**（门禁状态） | `build_local/step11/step11_verification_report.md` |
| 第 11 节原始结果 | `build_local/step11/step11_results.json` |
| **单砖 Starter 日志** | `build_local/step11/fe_one_brick/starter.log` |
| **单砖 Engine 日志** | `build_local/step11/fe_one_brick/engine.log` |
| 单砖求解原始输出 | `build_local/step11/fe_one_brick/`：`kf_law99_0000.out`、`.rst`、`A001`/`A002`（动画）、`T01` |
| **T01 转出的 CSV** | `build_local/step11/fe_one_brick/kf_law99T01.csv` |
| 运行时镜像（脚本自动生成） | `build_local/runtime/` |
| 材料点矩阵控制台日志 | `build_local/step11/material_point_matrix.log` |

只想看结论：两个 `.md` 报告。想看求解器是否正常：两个 `.log`。

**验收关键词**（打开日志搜这些字符串）：

- `starter.log` → `0 ERROR(S)`
- `engine.log` → `NORMAL TERMINATION`、`TOTAL NUMBER OF CYCLES`
- `kf_law99_0000.out` → `USER MATERIAL LAW99.02`、`Parameter set = input card`
  （这两行出现，说明求解器确实加载了动态库并从输入卡读到了 KF 参数）

---

## 10. 本机实测结果（2026-09-27）

与 `KF_LAW99_Guide.md` 第 7、8、11 节记录的原开发机结果一致。

### 材料点矩阵：8/8 PASS

```text
PASS hydrostatic_compression          PASS simple_shear
PASS large_hydrostatic_compression    PASS rate_effect
PASS uniaxial_compression             PASS corotational_objectivity
PASS uniaxial_tension                 PASS impact_rate_sweep
Overall: PASS
```

### 第 11 节清单：4 项自动化门 PASS，3 项 NOT_CERTIFIED

| 门 | 状态 | 关键量 |
|---|---|---|
| DLL material-point matrix | PASS | 8/8 检查通过 |
| P-alpha EOS consistency | PASS | 最大压力相对误差 = 0 |
| material-point step-size sensitivity | PASS | 32 vs 64 步应力相对差 1.704e-03 |
| OpenRadioss one-brick smoke and T01 integrity | PASS | starter 0 错误、engine 正常终止、CSV 4 行 × 55 列 |
| rate-effect calibration data gate | NOT_CERTIFIED | 需 SHPB 等动态实验数据标定 |
| impact benchmark gate | NOT_CERTIFIED | 需 SHPB / 平板撞击 / 侵彻 / 爆炸 FE 基准 |
| mesh-objectivity gate | NOT_CERTIFIED | 损伤尚无特征长度或断裂能正则化 |

> 3 项 `NOT_CERTIFIED` 是**预期**的，与原指南第 11 节说明一致，不是本机适配引入的失败。

### 单砖 FE 求解

```text
Starter : 0 ERROR(S) / 2 WARNING(S)
          （warning 为 /IOFLAG 与 /DEF_SOLID 的旧格式字段，与 J2 示例相同）
Engine  : NORMAL TERMINATION，TOTAL NUMBER OF CYCLES : 8
材料 echo: USER MATERIAL LAW99.02 ... Parameter set = input card
T01→CSV : 4 行 × 55 列，时间步 2.69E-04（为正），最终质量 1.0E+04，内力 4.06E+04
```

---

## 11. 未适配 / 未验证的部分

- **`examples/userlib/j2_law99`（v1 基线）未适配。** 它共用同一套 LAW99 接口，
  理论上照搬本文流程即可（改 `-S` 的源码目录和 `--dll` 路径），但没有实际跑过。
- **本机结果只验证了"接口连线 + 材料点数值行为 + 单砖求解闭环"**，
  不等于实验标定，也不等于复杂 FE 冲击算例验证——这一点与原指南第 8 节的说明相同。
- 与原指南第 9 节列出的功能升级计划（有限应变、损伤正则化等）无关，本文不涉及。

---

## 12. 后续可做

- 把 `run_local_kf.bat` 里的两处绝对路径（MinGW 根目录、`Tools` 仓库位置）改成可配置，
  便于换机器。目前它们只在这台机器上成立。
- 若要报告里也包含 `Build KF LAW99 DLL` 门，可给 `run_step11_validation.py` 加一个
  `--cmake` + 非 VS 构建目录的支持（需改脚本，本次刻意未改）。
- 编译 `th_to_csv` 时目前用 `-w` 屏蔽了源码里的 K&R 风格警告（`-Wold-style-definition`），
  这些警告无害。
