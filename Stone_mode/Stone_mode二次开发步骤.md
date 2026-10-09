# Stone_mode 二次开发步骤（KF 混凝土用户材料）

本文记录如何把 `LECMUSER01.f` + `LUSER01.f`（KF 混凝土损伤本构，移植自 LS-DYNA UMAT41 / MAT_072R3）
做成 OpenRadioss 的**动态用户库**并跑通，产出可在 HyperView 中查看的结果。

- 首次打通日期：2026-10-09
- 一键入口：`run_stone.bat`（在 `cmd.exe` 里运行或双击；**不要从 Git Bash 启动**）
- 全部产物落在 `Stone_mode\build_local\`，`Tools` 仓库只读不写

---

## 0. 先分清两条二次开发路线

本机现在有两个二次开发项目，走的是**完全不同的两条官方路线**，别混：

| | liruiw 项目（KF LAW99） | **本项目 Stone_mode** |
|---|---|---|
| 路线 | 动态用户库，**纯 C** | 动态用户库，**Fortran 侧 SDK** |
| 用户代码 | `raduser_kf_law99.c` | `LECMUSER01.f` + `LUSER01.f` |
| 需要 SDK 吗 | 不需要（只有 libc 依赖） | **需要**，`Tools\userlib_sdk` |
| 材料卡 | `/MAT/USER02` | `/MAT/USER01` |
| 求解器 LAWS 号 | 都是 `ILAW = 99` | 都是 `ILAW = 99` |
| 交换数据的结构 | 自定义 C struct | SDK 的 `ULAWBUF` / `ULAWINTBUF` |

两条路线产出的 DLL **同名**（`libraduser_win64.dll`），所以**必须各自独立构建到不同目录**，不能混用。

---

## 1. 术语表（先说清，避免路径歧义）

| 术语 | 指什么 |
|---|---|
| OpenRadioss 仓库 | `G:\Postgraduate_Researching\openSource_soft\OpenRadioss` |
| Tools 仓库 | `G:\Postgraduate_Researching\openSource_soft\Tools`（**兄弟仓库，不在 OpenRadioss 里**） |
| userlib_sdk | `Tools\userlib_sdk`，官方 Fortran 侧用户子程序 SDK |
| **SDK 静态库** | `libraduser_win64_gfortran.a` + 8 个 `*.mod`。**官方不预编译，必须自己建** |
| 用户库 / DLL | `libraduser_win64.dll`，求解器用 `-dylib` 加载 |
| starter 侧例程 | `LECMUSERnn`（读参数、算参数），本例 `LECMUSER01` |
| engine 侧例程 | `LUSERnn`（算应力），本例 `LUSER01` |
| `.scr` 中间文件 | starter 把 `/MAT/USER01` 的数据行转存成 `SI<root>_0099.scr` 供 starter 侧例程读 |
| `cm(1:48)` | LS-DYNA UMAT41 的 48 个参数，与 `uparam(1:48)` 一一对应 |

---

## 2. 调用链全景（这是理解一切的钥匙）

```
deck: /MAT/USER01/1
 │
 ├─ starter  hm_read_mat.F90:1385   case 'USER01'..'USER99'
 │            → ilaw = 99（固定）, iuser_law = nn（01..99）
 │    │
 │    └─ hm_read_mat_user_99.F
 │         · HM_GET_INTV('Number_of_datalines')  ← 卡里数据行的条数
 │         · 第 1 条数据行：READ(…,'(2F20.0)') RHO0, RHOR → PM(1)=RHOR, PM(89)=RHO0
 │         · 第 2..N 条数据行：逐行 TRIM 后写入 SI<root>_0099.scr
 │         │
 │         └─ ST_USERLIB_LECM99     dyn_userlib.c:463   ← 从 DLL 动态查找符号
 │              └─ ST_LECM99        win64_gfortran_wrapper.c:69  ← gfortran 侧导出名
 │                   └─ st_lecm99.F  SDK（-fno-underscoring，符号是小写）
 │                        └─ LECMUSER01(IIN,IOUT,UPARAM,MAXUPARAM,NUPARAM,
 │                                       NUVAR,IFUNC,MAXFUNC,NFUNC,PARMAT,USERBUF) ← 11 实参
 │                             ★ Stone_mode\LECMUSER01.f
 │                               · 从 SI<root>_0099.scr 读 6 行 × 8 个 F10.0 → cm(1:48)
 │                               · 填 UPARAM(48) / NUVAR=12 / NFUNC=0 / PARMAT(1:3)
 │                               · 通过 USE ST_ULAW 里的模块变量 USERBUF 回传 ID/NAME
 │
 ↓  starter 写出 restart（.rst），engine 读它
 │
engine: /MAT/USER01  (ILAW=99)
 └─ usermat_solid.F:1008   ENG_USERLIB_SIGEPS99
      └─ ENG_SIGEPS99 → eng_sigeps99.F
           └─ LUSER01(NEL,NUPARAM,NUVAR,NFUNC,IFUNC,NPF,TF,TIME,TIMESTEP,
                      UPARAM,RHO,VOLUME,EINT,NGL,SOUNDSP,VISCMAX,
                      UVAR,OFF,SIGY,PLA,ULAWVAR_ARRAY(ITASK))     ← 21 实参
                ★ Stone_mode\LUSER01.f
                  · 从 USERBUF（ULAWTNTBUF）取 sigoxx…depsxz
                  · KF 本构：三轴强度面 + 10 段 EOS + 损伤
                  · 写回 USERBUF%signxx…%dpla；SIGY/PLA 走独立形参
           └─ ENG_USERLIB_SET_LAW_VAR  把 USERBUF 结果写回求解器
```

**关键推论**：`LECMUSER01` / `LUSER01` 的实参个数和顺序是**由 SDK 钉死的**，不是自由写法。
本项目的两个文件与 SDK 完全一致，因此**一个字都不用改**。

---

## 3. 前置条件

| 项 | 本机值 |
|---|---|
| 编译器 | MinGW-w64 gfortran **15.2.0**：`G:\x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0\mingw64` |
| CMake | 4.2.3（`G:\Program Files\CMake\bin`） |
| Ninja | `OpenRadioss\extlib\build_mingw64\bin\ninja.exe` |
| 求解器 | `exec\starter_win64_gf.exe`、`exec\engine_win64_gf.exe`（双精度 gfortran 版） |
| Python | 3.x（只用来生成 deck） |

---

## 4. 步骤

### 步骤 1 — 建 SDK 静态库（一次性，约 1 分钟）

```bat
build_sdk.bat
```

做三件事：out-of-tree CMake 配置 → 编译 → 把 `.a` 和 `.mod` 摆成 `build_userlib.bat` 期望的布局
（`build_local\sdk\win64_gfortran\`）。

**为什么不用官方的 `build_windows.bat`？** 它会把 `cbuild_win64_gfortran_dp_ninja\` 和产物写进
Tools 仓库。本项目的 `sdk_src\CMakeLists.txt` 是官方那份的**镜像**，`include` 同一个
`cmake_win64_gfortran.txt`，只多一个 flag（见坑 1），产物全部落在项目内。

规模：**403 个目标文件**（34 个 `source\*.F` + 3 个 `source\*.c` + 369 个 `userlib_routines\*.F`
桩例程）。那 369 个桩不能删——`st_lecm99.F` / `eng_sigeps99.F` 的 dispatch 会引用
`LECMUSER01..99` / `LUSER01..99` 全部符号。

### 步骤 2 — 生成 deck

```bat
python make_deck.py
```

生成 4 个文件（SI 单位 kg, m, s, Pa）：

| 文件 | 内容 |
|---|---|
| `deck\stone_kf_0000.rad` / `_0001.rad` | 单砖（1 单元 8 节点），接口验证 |
| `deck\stone_axial_0000.rad` / `_0001.rad` | 10×4×4 = 160 单元，看应力/损伤分布 |

材料卡是全项目**唯一**的固定列宽卡，必须严格照格式（见坑 3）：

```
/MAT/USER01/1
STONE KF CONCRETE
#                 RHO                RHO_R
                2500                2500      ← 2 个 F20.0 字段
#   fc (Pa) ...
  -3.5E+07         0         0 ...            ← 6 行 × 8 个 F10.0 = cm(1..48)
```

### 步骤 3 — 编用户库 DLL

```bat
set RAD_USERLIB_SDK_PATH=<Stone_mode>\build_local\sdk
set RAD_USERLIB_ARCH=win64_gfortran
cd <Stone_mode>\build_local\stone_dll
<Tools>\userlib_sdk\userlib_sdk\win64_gfortran\build_userlib.bat ^
    /STARTER "..\..\LECMUSER01.f" /ENGINE "..\..\LUSER01.f"
```

`run_stone.bat` 已封装这一步。

### 步骤 4 — 跑

```bat
starter_win64_gf.exe -i stone_kf_0000.rad -dylib libraduser_win64.dll
engine_win64_gf.exe  -i stone_kf_0001.rad -dylib libraduser_win64.dll -nthread 2
```

需要的环境（脚本已设）：`RAD_CFG_PATH`、`RAD_H3D_PATH`、PATH 里加 MinGW `bin` 和 `extlib\build_mingw64`。

### 步骤 5 — 验证

```bat
run_stone.bat
```

---

## 5. 六个坑（按踩到的顺序）

### 坑 1：GCC 14+ 把 `implicit-function-declaration` 从警告升级成了错误

`source/interface_routines/win64_gfortran_wrapper.c` 里调用了大量**隐式声明**的 Fortran 入口
（它们都是 `SUBROUTINE`，即 void，隐式 `int` 返回类型一直无害），GCC 13 及以前只是警告，
GCC 14 起直接报 14 个 error，SDK 编译中断。

解决：C 编译参数追加 `-Wno-implicit-function-declaration`。
本项目写在自己的 `sdk_src\CMakeLists.txt` 里，**不动 Tools 仓库**：

```cmake
include ("${source_directory}/Cmake_Compilers/cmake_${arch}_${compiler}.txt")
# --- 唯一的偏离 ---
set (C_Compiler_flags "${C_Compiler_flags} -Wno-implicit-function-declaration")
```

> 若你想改用官方 `build_windows.bat`，需要往
> `Tools\userlib_sdk\source\Cmake_Compilers\cmake_win64_gfortran.txt` 的
> `C_Compiler_flags` 里加同一个 flag。

### 坑 2：SDK 的目录名套了两层 `userlib_sdk`

```
Tools\userlib_sdk\                      ← 仓库根
├── source\                             ← SDK 源码
├── userlib_routines\                   ← 桩例程
└── userlib_sdk\                        ← 再一层！
    ├── win64_gfortran\build_userlib.bat   ← 真正的构建脚本在这里
    └── win64_gfortran\                    ← 预编译库的“坑位”（官方发货时是空的）
```

所以脚本路径是 `Tools\userlib_sdk\userlib_sdk\win64_gfortran\build_userlib.bat`。
少写一层会得到 `build_userlib.bat not found`。

### 坑 3：`/MAT/USER01` 是固定列宽卡，不是自由格式

| 行 | 格式 | 说明 |
|---|---|---|
| 第 1 条数据行 | `(2F20.0)` | 两个 20 宽字段，**密度要两格都填** |
| 第 2..7 条数据行 | `(8F10.0)` × 6 | 每行 8 个 10 宽字段，共 48 个数 = `cm(1..48)` |

- 密度行依据：liruiw 里已验证可跑的 `kf_law99_0000.rad` 两格都写同一个值；且
  `hm_read_mat_user_99.F` 里 `PM(1)=RHOR`（**第 2 格**）才是求解器真正用的密度，
  第 1 格给 `PM(89)`。两格都填最保险。
- `.scr` 写入时用了 `TRIM`，所以最后一格必须有内容（不能留空白），否则行会被截断。
- 数据行之间可以插 `#` 开头的注释行，reader 会跳过，不计入 `Number_of_datalines`。

### 坑 4：用户文件名必须叫 `lecmuser01.f` / `luser01.f`

`build_userlib.bat` 的机制是：

1. `ar -x` 把静态库**全部解开**到 `_obj_win64\`；
2. 编译用户源码，输出 `%%~nf.obj`（**按源文件基名**）到同一个目录。

于是用户的 `LECMUSER01.f` → `LECMUSER01.obj`，在 Windows 大小写不敏感的文件系统上
**覆盖**掉解出来的 `lecmuser01.obj` 桩对象。链接时就没有重定义了。

改名成 `my_material.f` 会直接得到 duplicate symbol。

### 坑 5：`.bat` 必须存成 CRLF 行尾，且必须纯 ASCII

- **CRLF**：cmd.exe 按字节偏移读写 `.bat`。LF-only 的文件配合 `call` / `goto` 会**错位执行**，
  症状是控制台冒出 `'This' 不是内部或外部命令` 这类莫名其妙的报错（本项目的 `run_stone.bat`
  一开始就中招了）。用 `sed -i 's/\r*$/\r/'` 或编辑器「另存为 CRLF」修。
- **纯 ASCII**：cmd.exe 按 OEM 代码页（中文 Windows 上是 GBK）读 `.bat`。UTF-8 中文注释会被
  解码错位，而且 `rem` 行里的 `&` 仍会**切断命令**。中文一律放在 `.md` 里。

### 坑 6：`LECMUSER01.f` 其实是无条件覆盖全部 48 个参数

文件第 167~221 行的注释写的是「若 fc < 0，按 48MPa 混凝土经验公式生成全套参数」，
但**代码里没有那个 `if` 分支**——它是无条件执行 `fc = -fc`，然后用经验公式重建
`els_mol / k / g / t / k1..k10 / miu1..miu10 / p1..p10 / a1 / a2 / d1 / d2 / d3 / frac / row0 / dc_mode`。

**后果**：deck 里 `/MAT/USER01` 那 48 个字段，目前**只有第 1 个（fc）有效**，其余 47 个填什么都一样。
`make_deck.py` 因此把其余 47 格全填 0，并在注释里写明。

若要让 48 个参数真正可输入，需要给这段加上 `if (fc .lt. 0.0d0) ... end if` 保护——
本次按「项目源码逐字节不动」的原则没有改。

---

## 6. 本机实测结果（2026-10-09）

### 单砖 `stone_kf`（1 单元）

```text
Starter : 0 ERROR(S) / 2 WARNING(S)   ← warning 是 /IOFLAG 与 /DEF_SOLID 的旧格式字段，与 liruiw 相同
Engine  : NORMAL TERMINATION，TOTAL NUMBER OF CYCLES : 15
产物    : stone_kfA001..A010（10 帧）+ stone_kf.h3d + stone_kfT01
```

**参数 echo（starter 的 `.out` 第 219 行起）与手算完全一致**，证明 starter 侧例程确实执行：

| 量 | echo 值 | 手算 |
|---|---|---|
| fc | 0.3500E+08 | 3.5e7 Pa（35 MPa） |
| els_mol | 0.2800E+11 | ACI 4700√fc' = 2.80e10 Pa |
| k | 0.1556E+11 | E/(3(1−2ν)) = 1.556e10 |
| g | 0.1167E+11 | E/(2(1+ν)) = 1.167e10 |
| t | 0.3218E+07 | 3.22 MPa |
| a2 | 0.7143E-09 | 0.025/fc = 7.143e-10 |
| row0 | 0.2500E+04 | 来自 deck |

`.out` 第 353 行 `MATERIAL : 1 (LAW 99), STONE KF CONCRETE` 还证明标题经
`ST_GET_USERBUF_VAR` 从 DLL 回传成功。

### 材料响应（符合 KF 本构，非弹性）

| t | SX (Pa) | SY=SZ | 密度 | PLAS（损伤） |
|---|---|---|---|---|
| 2.83e-4 | −8.27e6 | −8.3e5 | 2500.5 | 0.046 |
| 7.08e-4 | −1.97e7 | +4.1e5 | 2501.0 | 0.064 |
| 1.28e-3 | −3.48e7 | +4.1e3 | 2501.8 | 0.084 |
| 1.84e-3 | −4.08e7 | −1.6e6 | 2501.2 | 0.119 |

读法：
- 加载面节点 X 速度全程 **恰为 1.0 m/s**，固定面为 0 —— `/IMPVEL` 生效
- 早时刻 `SX /(E·ε) = 8.27e6 / 7.93e6 = 1.043`，**与弹性解差 4%**（动态波效应）
- 末时刻纯弹性应为 5.15e7，实测 4.08e7（低 21%）—— 已进入强度面并沿硬化段走
- `SY = SZ` 且比 `SX` 小两个量级（单轴、侧面自由）
- 密度从 2500 升到 ~2501.8 后回落 —— EOS 压实；末时刻相对体积 VOL = 0.99954
- `PLAS` 单调增长 0 → 0.119 —— 这就是 `LUSER01` 里 `pla(i) = uvar(i,9)` 写出的 KF 总损伤 η

> **`/TH/BRIC` 的变量必须显式点名。** `make_deck.py` 里写的是
> `SX SY SZ PLAS DENS VOL` 而不是 `DEF`，因为 `DEF` 默认集**不含** `PLAS`（通道 12）。
> 通道号见 `engine/source/output/th/thsol.F:62` 的图例：
> `1=OFF 2=SX 3=SY 4=SZ 5=SXY 6=SYZ 7=SXZ 8=IE 9=DENS 10=BULK 11=VOL 12=PLAS …`。
> starter 会**按通道号排序**输出，所以写 `SX SY SZ PLAS DENS VOL` 出来的顺序是
> `SX SY SZ DENS VOL PLAS` —— 不要按书写顺序读列。

### 多单元 `stone_axial`（160 单元）

```text
Starter : 0 ERROR(S)
Engine  : NORMAL TERMINATION，TOTAL NUMBER OF CYCLES : 142
产物    : stone_axialA001..A010 + stone_axial.h3d（175 KB）+ stone_axialT01
```

**沿 X 的轴向应力 SX（Pa）——单砖版看不到的东西：**

| t | EX1 (x≈0.05) | EX5 (x≈0.45) | EX10 (x≈0.95) |
|---|---|---|---|
| 2.13e-4 | −7.88e6 | −8.06e6 | **−1.40e5** |
| 4.11e-4 | −7.87e6 | −7.84e6 | −1.49e7 |
| 1.81e-3 | −3.66e7 | −3.42e7 | −3.37e7 |

- 首行是**压缩波前**：t=2.13e-4 时波还没传到固定端，EX10 比别处小两个量级
- 波速 `c = √((k + 4g/3)/ρ) = 3527 m/s`，跨 1 m 需 **2.84e-4 s**；
  t=2.13e-4 时波前应在 x≈0.75 m —— 正好落在 EX10 之前。**完全吻合**
- 次行是波在固定端**反射叠加**
- 末行趋于均匀，散布 ±5% 来自波振荡

**末时刻各单元的 KF 总损伤 PLAS**（0.1555 ~ 0.1643，沿 X 分布略有差异）：
这是单砖版（一个单元只有一个值）看不到的东西。

---

## 7. 报错对照表

| 现象 | 原因 | 处理 |
|---|---|---|
| starter：`ERROR 1130 /MAT/USER01` 后 `ARRET` | 没加载到用户库（`USERL_AVAIL==0`） | 检查 `-dylib` 路径，或设 `RAD_USERLIB_LIBPATH` |
| starter 能跑但 `.out` 里没有 `kf user01 units:` 那几行 echo | DLL 里没有 `ST_LECM99` 符号 | 用 `nm`/`objdump` 看 DLL 导出；确认 `win64_gfortran_wrapper.c` 参与了链接 |
| 链接期 `duplicate symbol lecmuser01` | 用户文件基名不是 `lecmuser01` | 改回 `lecmuser01.f` / `luser01.f` |
| starter 报读 `.scr` 失败 / 参数全 0 | 数据行不是固定列宽，被 `TRIM` 截断 | 按坑 3 重排 |
| `build_userlib.bat not found` | 少写了一层 `userlib_sdk` | 见坑 2 |
| 控制台冒出 `'xxx' 不是内部或外部命令` | `.bat` 是 LF 行尾或含中文 | 见坑 5 |
| 求解器退出码 `3221225785` 且无输出 | 从 Git Bash 启动导致 PATH 被改坏 | 用 `cmd //c ".\run_stone.bat"` |

---

## 7.5 顺带发现的 SDK 自身缺陷（与本例无关，但别踩）

对 400 个 `.F` 做静态扫描（并用 gfortran 预处理核对）后，发现 SDK 里有几处**编译期查不出来**的问题，
因为整个源码集**没有任何 `INTERFACE` 块**，gfortran 无法诊断跨文件实参不匹配：

| 位置 | 问题 |
|---|---|
| `source\interface_routines\st_lecm.F:87` | 以 10 个实参调 `LECM30`，而 `userlaw29_31\lecm30.F` 声明 11 个（少 `UNITAB`） |
| `source\interface_routines\st_lecr.F:87` / `:91` | 以 10 个实参调 `LECR05` / `LECR06`，而它们声明 9 个（多 `ID`） |
| `source\interface_routines\st_lecsen.F:79-90` | `TYP` 为 29/30/31 时都调 `LECSEN_USR1`；`LECSEN_USR2/USR3` 定义了却从不调用，疑为复制粘贴缺陷 |

**影响范围**：LAW 29-31 与 rupture 接口。本例走的是 LAW 99 / `LECMUSER01` / `LUSER01` 这条路径，
**完全不受影响**。若将来要用那两类接口，这三处需要自己核对。

另外两条实测澄清：

- gfortran 的预处理器**不定义 `_WIN64`**（`gcc` 会定义）。所以 SDK 里 32 处
  `#ifdef _WIN64` 包裹的 `!DEC$ ATTRIBUTES ...` 长注释行（有的近 500 列）在本机**全部不激活**，
  `-ffixed-line-length-132` 不会截断它们。若你手动加了 `-D_WIN64`，就得再补
  `-ffixed-line-length-none`。
- 因此 **不需要** `-fallow-argument-mismatch` / `-std=legacy` / `-w`；
  唯一必需的额外 flag 就是坑 1 那一个。

---

## 8. 结果怎么看

```text
HyperView → File → Open → Results → 选 build_local\view_kf\stone_kfA001
读取器选 RADIOSS (A) Result Reader
```

`A002 … A010` 会自动一起读入，共 10 帧。可看：`Stress`（张量，可展开 SX/SY/SZ…）、
`Von Mises`、`Plastic Strain`、`Density`、`Displacement`。

**H3D**（`stone_kf.h3d` / `stone_axial.h3d`）里额外带 KF 状态变量
（`/H3D/SOLID/USER/UVAR=5/9/10/12`，即 λ_c、总损伤 η、等效塑性应变、λ_t），
但格式是 **v24**，本机 HyperWorks 14 读不了，需要 2021+ 版。

---

## 9. 文件清单

| 文件 | 说明 |
|---|---|
| `LECMUSER01.f`、`LUSER01.f` | 用户例程，**未改动** |
| `build_sdk.bat` | 步骤 1：建 SDK 静态库（可重复运行，已建则跳过） |
| `sdk_src\CMakeLists.txt` | SDK 构建的项目内镜像（含坑 1 的 flag） |
| `make_deck.py` | 步骤 2：生成全部 4 个 deck |
| `run_stone.bat` | 一键：SDK → deck → DLL → starter → engine（两个算例） |
| `deck\*.rad` | 生成的 deck（可随时重生成） |
| `build_local\` | 全部产物（可整目录删除重来） |

重跑全部：双击 `run_stone.bat`。只重建 SDK：`build_sdk.bat /FORCE`。
