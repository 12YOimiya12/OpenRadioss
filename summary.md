# OpenRadioss 工作小结

**统计区间：2026-09-08 ~ 2026-10-08**
**仓库：`G:\Postgraduate_Researching\openSource_soft\OpenRadioss`**
**分支：`main`，区间内 9 次提交（均为本人提交）**

---

## 一、总体进展

一个月内的工作可以概括为一句话：

> 把本机的 OpenRadioss 从**"源码能编译"**推进到**"能跑通二次开发本构、并产出可在前后处理软件中查看的结果"**。

按时间分三个阶段：

| 阶段 | 时间 | 主要工作 | 产出 |
|---|---|---|---|
| 一、求解器本机构建与跑通 | 09-09 ~ 09-17 | CMake 配置排错、MinGW gfortran 构建、冒烟测试 | `exec/starter_win64_gf.exe`、`exec/engine_win64_gf.exe` |
| 二、整机级工程算例 | 09-22 ~ 09-25 | 鸟撞风挡、气囊展开两个完整算例 | 鸟撞 101 帧动画、气囊 61 帧动画 |
| 三、二次开发（本构 LAW99） | 09-27 ~ 09-30 | KF LAW99 项目迁移、本机适配、验证、后处理打通 | 一键脚本 + 适配文档 + 三套可后处理算例 |

---

## 二、阶段一：求解器本机构建与跑通（09-09 ~ 09-17）

本机没有安装 Visual Studio，需要用仓库自带的 MinGW gfortran 工具链自行构建。

### 2.1 构建配置排错

- 处理 CMake 配置阶段的反复报错（CMake 4.2.3 + MinGW Makefiles 生成器，
  `build/.cmake/api/v1/reply/` 下留有 09-09 ~ 09-15 的多次 "no buildsystem generated" 失败记录）。
- 修复根目录 `CMakeLists.txt`：`if(${build} STREQUAL ...)` → `if("${build}" STREQUAL ...)`。
  变量展开后未加引号时，新版 CMake 会解析失败，加引号后兼容。
- 使用仓库自带的 `build_mingw64.sh` 流程，分别构建 starter 与 engine。

### 2.2 构建结果

| 可执行文件 | 大小 | 完成时间 |
|---|---|---|
| `exec/engine_win64_gf.exe` | 36.4 MB | 2026-09-15 16:50 |
| `exec/starter_win64_gf.exe` | 23.5 MB | 2026-09-15 20:24 |

文件名带 `_gf` 后缀，表示 gfortran 构建（与官方安装包的 MSVC 版本相区分）。

### 2.3 跑通性验证

- **冒烟测试**：`qa-tests/run_smoke/`（TWISBEAM，扭转梁收敛性算例），确认 Starter / Engine 全链路正常。
- **LS-DYNA 卡兼容性**：`qa-tests/run_dyna/`（`minimal.key`），验证 `.k` 格式的 LS-DYNA 输入卡可直接送入 OpenRadioss 求解。
- 配置了 `.vscode/launch.json` 便于调试启动。

### 2.4 代码理解

- 绘制 `OpenRadioss_architecture.drawio` + 预览图，梳理求解器整体架构。
- 首个提交 `test：ver1`（2026-09-15）。

---

## 三、阶段二：整机级工程算例（09-22 ~ 09-25）

在自建求解器上跑通两个完整的工程级算例，验证求解器处理实际问题的能力。

### 3.1 鸟撞风挡（Bird Strike）

- 目录：`BirdStrike/`，算例来自 OpenRadioss 官方 Example 49。
- 模型：SPH 粒子模拟鸟体（`PROP34_bird.txt`）+ 风挡壳体，共 6.4 MB 输入卡。
- **结果**：Starter `0 ERROR(S)`；Engine **NORMAL TERMINATION**，16634 个循环。
  计算耗时 3042 s（约 50 分钟），内存占用 266 MB，输出 101 帧动画。
- 一键脚本：`BirdStrike/run/run_birdstrike.bat`。
- 另做了 H3D 输出的兼容性试探（`BirdStrike/run_h3d/`，见 4.4 节）。

### 3.2 气囊展开（Airbag Deployment）

- 目录：`airbag/`，输入卡为 LS-DYNA 格式的 `airbag_deploy.k`（420 KB）。
- **结果**：产出 61 帧动画。最后一次运行的日志在写到第 42 帧（A042）时被手工中断（CTRL-C），
  未跑到自然终止。
- 一键脚本：`airbag/run/run_airbag.bat`。

### 3.3 仓库整理

- `fbb40a927` / `909474ac0` / `21649d9e7`：把散落的本地改动合并为单一提交，并把
  构建产物（`build/`、`*.obj`、`*.dll` 等）与仿真输出（`A0xx`、`.rst`、`.h3d` 等）排除出版本库。

---

## 四、阶段三：二次开发 —— KF LAW99 本构（09-27 ~ 09-30）

这是本月最核心的工作。**二次开发**指在开源求解器基础上扩展其能力，本项目的切入点是
**材料本构模型（LAW）**——即"应力怎么随应变演化"的数学规则。

### 4.1 项目背景与迁移

李瑞文的 KF（Kong-Fang）本构模型二次开发项目，以 **LAW99 动态用户库**的形式实现：

- 材料卡 `/MAT/USER02`，OpenRadioss 内部映射到 `ILAW=99`，再调用动态库中的用户本构。
- 25 个 KF 参数（弹性模量、强度面、损伤参数、P-alpha 状态方程参数等）。
- 8 个状态变量（损伤 D、孔隙变量 α、等效塑性应变、压力 P、屈服强度、应变率、相对体积 J 等）。
- 附带 DLL 级材料点验证矩阵（8 项）与"第 11 节"验证清单。

该项目原本在另一台机器上、基于 **MSVC + Visual Studio 2022** 开发。本机没有 VS，
需要迁移到 **MinGW gfortran** 环境。

**迁移结论：改动极小。** 先读求解器源码确认了三件事，因此**不必重新编译求解器，也不必修改项目任何源码、脚本或测试卡**：

1. 本机 gfortran 求解器已内置动态用户库支持（`dyn_userlib.c` 已在构建中）。
2. 用户库 DLL 的文件名两套工具链下完全一致（`libraduser_win64.dll`），无需改名。
3. DLL 源码是纯 C，不依赖 Fortran SDK。

### 4.2 本机适配成果

新增两个文件（`liruiw/` 目录下）：

| 文件 | 作用 |
|---|---|
| `run_local_kf.bat` | 一键脚本：编译 DLL → 搭运行时镜像 → 跑材料点矩阵 → 跑第 11 节清单 |
| `KF_LAW99_Local_Adaptation.md` | 适配文档（环境对照、手工命令、坑、产物速查、实测结果） |

脚本 5 步全自动，任一步失败即中止；所有产物落在 `build_local/`，不污染其他目录。
换机器时只需改脚本顶部 CONFIG 段的两个路径（也可用环境变量覆盖）。

**踩到并解决了 4 个坑**（已写入文档）：

1. **必须用 ninja，不能用 `mingw32-make`** —— 仓库路径含中文时 make 会报
   `Illegal byte sequence` 而无法编译。
2. **`libgcc_s_seh-1.dll` 必须与用户库 DLL 放同一目录** —— Python 3.8 以后
   `ctypes` 不再通过 PATH 解析依赖 DLL，否则加载用户库直接失败。
3. `--skip-build` 的原因 —— 原验证脚本写死了 VS 工程目录，本机不存在，跳过该门。
4. **不要从 Git Bash 启动求解器** —— Git Bash 会破坏 PATH 中的路径，求解器静默失败
   （退出码 0xC0000142、无输出）。

### 4.3 验证结果（与原开发机结论一致）

**DLL 材料点矩阵：8/8 PASS**

```text
PASS 静水压缩          PASS 简单剪切
PASS 大静水压缩        PASS 率效应
PASS 单轴压缩          PASS 共旋客观性
PASS 单轴拉伸          PASS 冲击率扫描
```

**第 11 节验证清单：4 项自动化门 PASS，3 项 NOT_CERTIFIED**

| 门禁 | 状态 |
|---|---|
| DLL 材料点矩阵 | PASS（8/8） |
| P-alpha 状态方程一致性 | PASS（最大压力相对误差 = 0） |
| 材料点步长敏感性 | PASS（32 vs 64 步，应力相对差 1.7e-03） |
| 单砖 FE 冒烟 + T01 完整性 | PASS（Starter 0 错误、Engine 正常终止） |
| 率效应标定数据门 | NOT_CERTIFIED（缺 SHPB 等动态实验数据） |
| 冲击基准门 | NOT_CERTIFIED（缺平板撞击/侵彻/爆炸 FE 基准） |
| 网格客观性门 | NOT_CERTIFIED（损伤尚无特征长度或断裂能正则化） |

> 3 项 NOT_CERTIFIED 是**预期结果**，与原指南说明一致，不是本机适配引入的失败。
> 它们本质上需要**实验数据**或**算法升级**，不是配置问题。

### 4.4 后处理（HyperView）打通

**做这件事的原因**：算例跑出 `.rst` / 动画文件还不够，要能**看出来**——云图、应力分布、
损伤演化，这是研究中真正要用的东西。

本机装的是 HyperWorks 14.0（2015 年版），遇到并解决了一个版本兼容问题：

- ❌ **H3D 路线走不通**：求解器写出的 H3D 是 v24 格式，HW14 的读取器读不了。
  换成 HW14 自带的 `h3dwriter.dll` 也不行——接口不兼容，引擎直接崩溃。
- ✅ **改用 RADIOSS 动画文件**：`/ANIM` 产出的 `A001` 文件 HW14 原生支持，
  可直接 `File → Open → Results` 打开。

**同时发现一个路径问题**：HW14 无法读取中文路径下的结果。为此把项目目录
从 `李瑞文/` 改名为 **`liruiw/`**（纯英文），结果即可直接打开，不再需要额外的镜像拷贝步骤。

新增三套可后处理算例（均改动输出卡，**模型/材料/载荷均未改动**）：

| 脚本 | 算例 | 内容 |
|---|---|---|
| `run_kf_view.bat` | `view_kf/` | KF LAW99 单砖，8 帧 |
| `run_j2_view.bat` | `view_j2/` | J2 塑性基线（v1），8 帧 |
| `run_kf_axial.bat` | `view_kf_axial/` | KF 多单元单轴压缩，10 帧 |

**关于 `view_kf_axial`（多单元版）**：原项目带的算例都是"单砖"（1 个单元、8 个节点），
在 HyperView 里整个模型只有一个应力值，云图是单一颜色，看不出分布。因此用 `make_deck.py`
生成了一个 **10×4×4 = 160 单元**的模型，其余设定（几何、材料卡、边界、载荷、时间）逐项照抄原算例。
实测 Engine 正常终止（75 个循环），能看出清晰的空间分布：

- 早时刻压缩波尚未传到固定端，固定端应力比其他位置小两个量级（**波前传播可见**）；
- 末时刻沿厚度形成明显梯度：加载端 −4.79e7 Pa、固定端 −7.01e7 Pa（反射叠加）；
- 量级与解析值 E×应变 = 5.59e7 Pa 一致。

结果同时输出为 H3D（含 KF 的 8 个状态变量），但需 2021 版以上 HyperWorks 才能打开。

**早期探索产物**（09-29，已被上面的正式算例取代，保留作记录）：
`demo2/run_kf_blast/`（KF 本构 + 爆炸载荷，30 帧动画）与仓库根 `view_kf/`（第一次打通 H3D 输出的尝试）。

### 4.5 补充完善（进行中，尚未提交）

- engine deck 增补应力/应变输出卡：`/ANIM/BRICK/TENS/STRESS`、`/ANIM/ELEM/VONM`、
  `/ANIM/ELEM/EPSP`、`/ANIM/BRICK/DENS`，以及 `/H3D/SOLID/TENS/STRESS`。
  此前动画文件里只能看位移矢量，看不出应力。
- 适配文档补写第 15 节（多单元单轴压缩算例），并修正第 14 节中的个别表述。

---

## 五、当前状态

### 已提交（9 次提交）

```text
2b18af726  2026-09-30  j2_law99 本机适配并输出可后处理结果；项目目录改名为 liruiw
3f9c74b6b  2026-09-29  KF LAW99 本机 MinGW 适配：新增一键脚本与适配文档
e20773c71  2026-09-27  kF-adapted_edit
0994c63b9  2026-09-27  2cikaifedit
21649d9e7  2026-09-25  合并本地改动为单一提交，排除构建产物与仿真输出
909474ac0  2026-09-25  final_
fbb40a927  2026-09-25  update ui ctrl
e02996f2f  2026-09-24  update notes
877187647  2026-09-15  test：ver1
```

### 尚未提交（工作区改动）

- 新增：`liruiw/run_kf_axial.bat`、`liruiw/view_kf_axial/`（含 `make_deck.py`）
- 修改：`liruiw/KF_LAW99_Local_Adaptation.md`（+88 行，第 15 节）、
  `liruiw/run_j2_view.bat`、`liruiw/run_kf_view.bat`、
  `liruiw/view_j2/law99_j2_0001.rad`、`liruiw/view_kf/kf_law99_0001.rad`

### 关键路径速查

| 内容 | 位置 |
|---|---|
| 求解器可执行文件 | `exec/*_gf.exe` |
| KF 一键运行（含全部验证） | `liruiw/run_local_kf.bat` |
| KF 适配文档 | `liruiw/KF_LAW99_Local_Adaptation.md` |
| KF 项目指南 | `liruiw/KF_LAW99_Guide.md` |
| 可后处理算例 | `liruiw/build_local/view_kf/`（及 `view_j2/`、`view_kf_axial/`） |
| 验证报告 | `liruiw/build_local/validation/`、`liruiw/build_local/step11/` |

---

## 六、遗留问题与后续方向

以下按**优先级**排列，前三项来自项目文档已列出的待办：

1. **参数标定（最关键）** —— 当前材料参数是示例值，只用于数值闭环测试，**不是真实材料参数**。
   需要静态压缩、拉伸、三轴压缩、SHPB 等实验数据来标定，否则本构没有实际预测能力。
2. **损伤正则化** —— 当前损伤模型没有特征长度或断裂能正则化，进入软化段后结果会依赖网格划分。
   这是"网格客观性门"未能通过的直接原因。
3. **有限应变框架** —— 当前是大转动 + 密度驱动的状态方程更新，不是完整的有限应变乘法塑性。
   若研究涉及大变形冲击，需要接入变形梯度信息、改用 Cauchy/Kirchhoff 应力度量。
4. **H3D 查看** —— 若能用上 2021 版以上的 HyperWorks，可直接查看 KF 的 8 个状态变量云图
   （当前只能用动画文件，看不到损伤、孔隙等内部变量）。
5. **`run_step11_validation.py` 的构建门** —— 脚本写死了 VS 工程目录，本机用 `--skip-build` 跳过，
   导致报告中缺少 "Build DLL" 一行。可给脚本加上非 VS 构建目录支持。
6. **提交工作区改动** —— 4.5 节的输出卡改动与新增的多单元算例尚未提交。
