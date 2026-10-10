# VS_OneAPI 二次开发步骤（VS2022 + oneAPI 路线）

本文记录如何用 **Intel oneAPI（ifx + icx）** 把 `LECMUSER01.f` + `LUSER01.f`
（KF 混凝土损伤本构，移植自 LS-DYNA UMAT41 / MAT_072R3）做成 OpenRadioss 的
**动态用户库**并跑通。

- 首通日期：2026-10-10
- 一键入口：`run_vs_oneapi.bat`（在 `cmd.exe` 里运行或双击；**不要从 Git Bash 启动**）
- 全部产物落在 `VS_OneAPI\build_local\`，`Tools` 仓库只读不写
- 同机的 MinGW gfortran 路线见 `..\Stone_mode\Stone_mode二次开发步骤.md`，两条路互不干扰

---

## 0. 这条路线和 Stone_mode 的区别

同样是 KF 混凝土、同样产出 `libraduser_win64.dll`，但**工具链完全不同**：

| | Stone_mode（gfortran） | **VS_OneAPI（本文）** |
|---|---|---|
| Fortran 编译器 | MinGW-w64 **gfortran 15.2.0** | Intel **ifx 2026.1.1** |
| C 编译器 | gcc | Intel **icx 2026.1.1** |
| 链接器 | MinGW ld | MSVC **14.44.35207** `link.exe` |
| SDK 静态库 | `libraduser_win64_gfortran.a` | `libraduser_win64_oneapi.lib` |
| 外部符号命名 | `-fno-underscoring` → 小写 `st_lecg` | 接口例程**大写** `ST_LECG`，其余小写 |
| C wrapper | **需要**（GCC 不认 `!DEC$`） | **不需要**（ifx 自己导出） |
| 材料卡 / LAWS 号 | `/MAT/USER01` / `ILAW=99` | 同左 |
| 用户源码 | 同一份，**未改动** | 同左 |

两条路产出的 DLL **同名**，所以必须各自独立构建到不同目录 —— 这就是本目录
独立于 `Stone_mode\` 的原因，别把两边的 DLL 混用。

---

## 1. 术语表

| 术语 | 指什么 |
|---|---|
| OpenRadioss 仓库 | `G:\Postgraduate_Researching\openSource_soft\OpenRadioss` |
| Tools 仓库 | `G:\Postgraduate_Researching\openSource_soft\Tools`（**兄弟仓库**） |
| userlib_sdk | `Tools\userlib_sdk`，官方 Fortran 侧用户子程序 SDK |
| **SDK 静态库** | `libraduser_win64_oneapi.lib` + 8 个 `.mod`。官方不预编译，必须自己建 |
| 用户库 / DLL | `libraduser_win64.dll`，求解器用 `-dylib` 加载 |
| 接口例程 | `source\interface_routines\*.F`，导出求解器要找的 ABI 名字 |
| 桩例程 | `userlib_routines\**`，每号 LAW 一个空壳，共 369 个 |
| starter 侧例程 | `LECMUSER01`（读参数、算参数） |
| engine 侧例程 | `LUSER01`（算应力） |
| `.scr` 中间文件 | starter 把 `/MAT/USER01` 数据行转存成 `SI<root>_0099.scr` 供 starter 侧例程读 |

---

## 2. 全景：谁调用谁

```
deck: /MAT/USER01/1
 │
 ├─ starter  读卡 → 写 SI<root>_0099.scr
 │    └─ dyn_userlib.c  LoadLibrary(libraduser_win64.dll)
 │         └─ GetProcAddress("ST_LECM99")        ← 大写！Windows 分支
 │              └─ st_lecm99.F (SDK 接口例程，!DEC$ ALIAS 钉成 ST_LECM99)
 │                   └─ LECMUSER01(...)          ← 小写无下划线
 │                        ★ LECMUSER01.f
 │
 ↓  starter 写 restart(.rst)，engine 读它
 │
engine: /MAT/USER01
 └─ dyn_userlib.c  GetProcAddress("ENG_SIGEPS99")
      └─ eng_sigeps99.F
           └─ LUSER01(...)
                ★ LUSER01.f
```

**两条命名约定并存，这是本路线最容易踩的地方：**

| 谁 | 符号形态 | 由什么决定 |
|---|---|---|
| 接口例程（`interface_routines/*.F`） | **大写** `ST_LECG` / `ENG_SIGEPS99` | 源码里的 `!DEC$ ATTRIBUTES ... ALIAS : "ST_LECG"` |
| 用户例程 + 桩例程 + C 辅助 | **小写、无尾下划线** `lecmuser01` / `arret` | 编译选项 `/names:lowercase /assume:nounderscore` |

验证方法：

```bat
dumpbin /directives st_lecg.F.obj        →  /EXPORT:ST_LECG
dumpbin /directives library_id.c.obj     →  /EXPORT:userlib_id
```

---

## 3. 前置条件

| 项 | 本机值 |
|---|---|
| Visual Studio 2022 | Professional 17.14.41，`G:\Program Files\visualStudio`（**非标准路径**） |
| MSVC 工具集 | 14.44.35207（`link.exe` / `lib.exe` / `dumpbin.exe`） |
| Windows SDK | 10.0.26100.0 |
| oneAPI | 2026.1.1，`G:\One_API`（**非标准路径**）；ifx / icx |
| CMake | VS2022 自带 3.31.6（`%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin`） |
| Ninja | `OpenRadioss\extlib\build_mingw64\bin\ninja.exe` |
| 求解器 | `exec\starter_win64_gf.exe` / `engine_win64_gf.exe`（**gfortran 版，不用重建**） |
| MinGW | `G:\x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0\mingw64`（求解器运行时需要） |

脚本里的路径都可用同名环境变量覆盖：`KF_VS2022` / `KF_ONEAPI` / `KF_MINGW` / `KF_TOOLS`。

---

## 4. 完整命令序列

### 4.1 一键

```bat
cd /d G:\Postgraduate_Researching\openSource_soft\OpenRadioss\VS_OneAPI
run_vs_oneapi.bat <starter_0000.rad> <engine_0001.rad> [线程数]
```

例：

```bat
run_vs_oneapi.bat ..\Stone_mode\deck\stone_kf_0000.rad ..\Stone_mode\deck\stone_kf_0001.rad 2
```

这一步内部依次做：起环境 → 建 SDK 静态库（已建则跳过）→ 编用户库 DLL →
跑 starter → 跑 engine，结果写在 `build_local\run\`。

### 4.2 分步（要看清楚每步在干什么时用这个）

#### Step 0 —— 起编译环境

`vs_env.bat` 做的三件事：

```bat
rem ① 唯一的实质修复：告诉 oneAPI 真正的 VS 在哪
set "VS2022INSTALLDIR=G:\Program Files\visualStudio"

rem ② 编译器临时文件收进项目内，别污染 %TEMP%
set "TEMP=%~dp0build_local\tmp"
set "TMP=%~dp0build_local\tmp"

rem ③ 初始化 13 个 oneAPI 组件
call "G:\One_API\setvars.bat" intel64
```

验证：

```bat
set "VS2022INSTALLDIR=G:\Program Files\visualStudio"
call "G:\One_API\setvars.bat" intel64
where ifx
where icx
where link
```

#### Step 1 —— 建 SDK 静态库（一次性，约 1 分钟）

```bat
build_sdk.bat
```

实际执行的命令：

```bat
"%CMAKE%" -G Ninja -S "sdk_src" -B "build_local\sdk_build_oneapi" ^
  -DSDK_SOURCE="..\..\Tools\userlib_sdk\source" ^
  -DCMAKE_MAKE_PROGRAM="..\extlib\build_mingw64\bin\ninja.exe" ^
  -DCMAKE_Fortran_COMPILER=ifx -DCMAKE_C_COMPILER=icx ^
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ^
  -Darch=win64 -Dcompiler=oneapi -Dprecision=dp

"%CMAKE%" --build "build_local\sdk_build_oneapi"
```

其中 `CMAKE` = VS 自带的 `cmake.exe`。做完把 `.lib` 和 `.mod` 摆成 SDK 期望的布局：

```
build_local\sdk\win64_oneapi\libraduser_win64_oneapi.lib
build_local\sdk\win64_oneapi\*.mod           （8 个）
```

规模：**802 个构建任务**。CMake 对 Fortran 走两步（`ifx -fpp -P` 预处理 +
编译），所以是 400 个 Fortran × 2 + 2 个 C。归档成员 **402 个**
（400 Fortran + `init_callback.c` + `library_id.c`）。

`userlib_routines\**` 下每号 LAW 一个空壳桩，**不能删** —— 接口例程的 dispatch
会引用全部 99 号 `LECMUSERnn` / `LUSERnn`。用户只替换其中 1 号，做法见 Step 2 ③。

#### Step 2 —— 编用户库 DLL

```bat
build_userlib.bat
```

内部五小步，展开就是：

**① 起环境**

```bat
call vs_env.bat quiet
```

**② 把 SDK 静态库全部解到 `_obj_win64\`**

```bat
pushd build_local\userlib_oneapi\_obj_win64
lib -list "<SDK>\libraduser_win64_oneapi.lib" | findstr /c:.obj > liblist.txt
for /f "delims=" %%f in (liblist.txt) do lib /NOLOGO /EXTRACT:%%f "<SDK>\libraduser_win64_oneapi.lib"
```

解出 **402 个 `.obj`**，成员名形如 `lecmuser01.F.obj`（`lib.exe` 会把
`CMakeFiles\...\` 那层路径压掉，全部平铺到当前目录）。

**③ 删掉被用户例程替换的桩对象**

```bat
del /q _obj_win64\LECMUSER01.F.obj
del /q _obj_win64\LUSER01.F.obj
```

> **这一步不能省。** 归档里每个 LAW 号都有一个空壳桩；命名约定统一之后，
> 用户的 `lecmuser01` 会和桩的 `lecmuser01` 重定义。NTFS 大小写不敏感，
> 所以写 `LECMUSER01.F.obj` 就能删掉解出来的 `lecmuser01.F.obj`。
> Stone_mode 那条 gfortran 路线靠的是"用户对象同名覆盖"的隐式技巧，
> 这里改成显式删除，更不容易看错。

**④ 编用户例程**

```bat
ifx /nologo /c /names:lowercase /assume:nounderscore /fpp /DMYREAL8 /DR8 ^
    /module:"<SDK>" /Qaxsse3 /Qimf-use-svml:true /align:array64byte /Qopenmp ^
    /O2 /fp:precise /Qftz /extend-source "..\..\LECMUSER01.f"

ifx /nologo /c /names:lowercase /assume:nounderscore /fpp /DMYREAL8 /DR8 ^
    /module:"<SDK>" /Qaxsse3 /Qimf-use-svml:true /align:array64byte /Qopenmp ^
    /O3 /fp:precise /Qftz /extend-source "..\..\LUSER01.f"
```

产出 `LECMUSER01.obj` / `LUSER01.obj` 在 `_obj_win64\` 里。

要点：
- `/module:"<SDK>"` —— 用户源码里 `use law_user` / `use law_userso`，
  这个选项**同时是搜索路径**，指到装 `.mod` 的目录。
- `/names:lowercase /assume:nounderscore` —— 必须和 SDK 静态库一致，
  否则调不通（见第 5 节）。

**⑤ 链接**

```bat
pushd build_local\userlib_oneapi
ifx /nologo /DLL /MT -o libraduser_win64.dll _obj_win64\*.obj
```

产出三个文件：`libraduser_win64.dll`（约 1.5 MB）、`.exp`、`.lib`（import library，不用管）。

`/MT` 让 MSVC 运行时静态链进去，少一个依赖。

#### Step 3 —— 跑

```bat
set "RAD_CFG_PATH=%REPO%\hm_cfg_files"
set "RAD_H3D_PATH=%REPO%\extlib\h3d\lib\win64"
set "RAD_USERLIB_LIBPATH=%~dp0build_local\userlib_oneapi"
set "PATH=%KF_MINGW%\bin;%KF_ONEAPI%\compiler\2026.1\bin;%RAD_H3D_PATH%;%REPO%\extlib\build_mingw64;%PATH%"

"%REPO%\exec\starter_win64_gf.exe" -i stone_kf_0000.rad -dylib "libraduser_win64.dll"
"%REPO%\exec\engine_win64_gf.exe"  -i stone_kf_0001.rad -dylib "libraduser_win64.dll" -nthread 2
```

> **PATH 里两边运行时都要有**，否则求解器在打印任何东西之前就死：
> `_gf` 求解器要 MinGW 的 `bin`，ifx 编的用户库可能在加载期拉 Intel 运行时 DLL。
> 症状是退出码 `0xC0000135`（STATUS_DLL_NOT_FOUND）或
> `0xC0000139`（STATUS_ENTRYPOINT_NOT_FOUND）。

`run_vs_oneapi.bat` 会把工作目录切到 `build_local\run\`，因为求解器把结果写在
**当前目录**，不切的话会散在仓库根目录。

#### Step 4 —— 验证导出表

```bat
check_exports.bat
```

它 `dumpbin /exports` 之后，逐个核对 `dyn_userlib.c` 在 Windows 分支要的全部符号：

- starter 必需 13 个：`ST_LECG` `ST_LECGUSER` `ST_LECM` `ST_LECR` `ST_LECM99`
  `ST_LECSEN` `ST_RINIUSER` `ST_SINIUSR` `ST_USERWIS` `ST_USERWIS_INI`
  `ST_GET_USERBUF_VAR` `userlib_id` `set_callback`
- engine 必需 20 个：`ENG_RUSER` `ENG_SIGEPS` `ENG_SIGEPSC` `ENG_FLAW` `ENG_FLAWC`
  `ENG_SIGEPS99` `ENG_SIGEPS99C` `ENG_GET_LAW_USER_VAR` `ENG_GET_LAW_USER_VAR_2`
  `ENG_SET_LAW_USER_VAR` `ENG_SET_LAW_USER_VAR_2` `ENG_GET_LAWC_USER_VAR`
  `ENG_GET_LAWC_USER_VAR_2` `ENG_SET_LAWC_USER_VAR` `ENG_SET_LAWC_USER_VAR_2`
  `ENG_GET_UINTBUF_VAR` `ENG_SUSER` `ENG_USERINT` `ENG_USERWI` `ENG_USER_SENS`

> `CINI29/30/31` 和 `ENGINE_USER_CHECK/INITIALIZE/FINALIZE` **不在**构建范围内，
> 属正常 —— `dyn_userlib.c` 里它们的 `err=err+1` 是注释掉的（可选）。

---

## 5. 五个关键设计点

### 5.1 ifx 路线上**不要**编 C wrapper

`Tools\userlib_sdk\source\interface_routines\win64_gfortran_wrapper.c` 是
**GCC 专用**的，它的 `#ifdef __GNUC__` 门不是缺陷。

SDK 的 Fortran 把 `!DEC$ ATTRIBUTES DLLEXPORT` 和 `ALIAS : "ST_LECG"` 一起包在
`#ifdef _WIN64` 里：

| | gfortran | ifx |
|---|---|---|
| `/fpp` 是否定义 `_WIN64` | ❌ | ✅ |
| 上面那两行指令 | 死代码 | **生效** |
| 接口例程符号 | 小写 `st_lecg` | **大写 `ST_LECG`** |
| 谁来导出 | 只能靠 C wrapper | **Fortran 自己**（`.drectve` 里带 `/EXPORT:`） |

所以 ifx 路线上 **Fortran 对象自带导出**，求解器要的名字全都有。再编那个
C wrapper 上去，它内部按**小写** `st_lecg(...)` 调用，而 **MSVC 链接器区分大小写**，
永远绑不上大写的 Fortran 符号 → 34 个 `unresolved external symbol`。

> 顺带澄清一个看着矛盾的点：官方 `cmake_win64_oneapi.txt` 里带 `/nofpp`，
> 但 ALIAS 却生效了 —— 因为 CMake 对 Fortran 走**两步**：先用
> `ifx -fpp ... -P` 生成 `st_lecg.F-pp.f`，再编译这个**已预处理**的文件。
> `#ifdef _WIN64` 在预处理阶段就展开成实代码，编译步带 `/nofpp` 已无所谓。

### 5.2 用户例程的命名约定必须和 SDK 一致

SDK 静态库用 `/names:lowercase /assume:nounderscore`，等价于 gfortran 的
`-fno-underscoring`：**小写、无尾下划线**。调度器按 `lecmuser01` / `luser01`
调用用户例程；`ARRET` 由 `source\interface_routines\init_callback.c` 提供，
**大写小写两个版本都有、都没有尾下划线**：

```c
void _FCALL ARRET(int * mode){  arret_p(mode);}
void _FCALL arret(int * mode){  arret_p(mode);}
```

用 `/assume:underscore` 编用户源码会得到 `ARRET_`，全数失配。

### 5.3 必须删掉被替换的桩对象

见 Step 2 ③。

### 5.4 求解器**不用重建**

`exec\` 里只有 gfortran 版（`_gf`），没有 `starter_win64.exe`。但**不需要**重编 ——
实测 gfortran 求解器能直接加载 ifx 编的 DLL：

- 两者产出的 DLL 同名，`dyn_userlib.c` 只按名字 `GetProcAddress`；
- SDK wrapper 的 C 边界**全是裸指针**（`int*` / `my_real*` / `char*`），
  没有传值结构体、没有 Fortran 派生类型跨界；
- 两条工具链的运行时各自独立，互不干扰。

### 5.5 `/MAT/USER01` 是固定列宽卡

沿用 Stone_mode 的结论：第 1 条数据行 `(2F20.0)`（密度两格都填），
第 2..7 条数据行 `(8F10.0)` × 6 = 48 个数。详见
`..\Stone_mode\Stone_mode二次开发步骤.md` 坑 3。

---

## 6. 本机实测结果（2026-10-10）

单砖算例 `stone_kf`（1 单元），与 gfortran 路线逐值对比：

| 项 | 结果 |
|---|---|
| starter | `0 ERROR(S)`；`kf user01 units: kg, m, s, pa.`；`user01 solid kf concrete law` |
| engine | `NORMAL TERMINATION`，`TOTAL NUMBER OF CYCLES : 15` |
| 导出符号 | **86 个**，Windows 分支要求的 13 + 20 个**全在** |
| `stone_kf.h3d` | **逐字节相同** |
| `stone_kfA001..A010` | **逐字节相同**（含末帧 A010） |
| `stone_kfT01` | 仅文件头日期串不同（`Fri Oct 9` / `Sat Oct 10`），**数值载荷逐位相同** |
| 接口版本号 | `2102011231` vs `2102011230` |

最后一条不是问题：`library_id.c` 里

```c
#ifdef GCC_COMP
#define TAG 2102011231
#else
#define TAG 2102011230
#endif
```

gfortran 那份配置带 `-DGCC_COMP`，oneAPI 的不带，**故意区分**。

---

## 7. 排错对照表

| 现象 | 原因 | 处理 |
|---|---|---|
| `setvars.bat` 报 `Visual Studio was not found`，13 个组件全报 `'vars.bat' 不是内部或外部命令` | VS 装在非标准路径 | 先 `set "VS2022INSTALLDIR=G:\Program Files\visualStudio"` |
| 链接期 34 个 `unresolved external symbol st_lecg` 之类 | 编了 GCC 专用的 C wrapper | 见 5.1，别编它 |
| `unresolved external symbol ARRET_` / `lecmuser01_` | 用户源码用了 `/assume:underscore` | 见 5.2，改 `/assume:nounderscore` |
| `error #7002: Error in opening the compiled module file [LAW_USER]` | 缺 `/module:"<SDK>"` | 见 Step 2 ④ |
| `error LNK2005: 已经在 *.obj 中定义` | 没删被替换的桩对象 | 见 Step 2 ③ |
| 求解器退出码 `0xC0000135`，无任何输出 | 缺运行时 DLL（MinGW 或 Intel） | 见 Step 3 的 PATH |
| 求解器退出码 `0xC0000139` | 同上，找到 DLL 但入口点不匹配 | 同上 |
| starter 报 `ERROR 1130 /MAT/USER01` | 没加载到用户库 | 查 `-dylib` 路径；用 `check_exports.bat` 核对导出 |
| 控制台冒出 `'xxx' 不是内部或外部命令`（.bat 自身） | .bat 是 LF 行尾或含中文 | 转 CRLF + 纯 ASCII |

---

## 8. 文件清单

| 文件 | 说明 |
|---|---|
| `LECMUSER01.f`、`LUSER01.f` | 用户例程，**未改动** |
| `vs_env.bat` | 起 Intel 环境（设 `VS2022INSTALLDIR` + `call setvars.bat`） |
| `build_sdk.bat` | Step 1：建 SDK 静态库（可重复运行，已建则跳过，`/FORCE` 强制重建） |
| `build_userlib.bat` | Step 2：编用户库 DLL；可传两个参数换用户源码 |
| `check_env.bat` | 环境自检：起环境 + configure `sdk_src`（**不编译**） |
| `check_exports.bat` | Step 4：核对 DLL 导出表 |
| `run_vs_oneapi.bat` | 一键：构建 + 跑 starter/engine |
| `sdk_src\CMakeLists.txt` | 官方 CMakeLists 的项目内镜像（**唯一需要改动的构建文件**） |
| `build_local\` | 全部产物，可整目录删除重来 |

重跑全部：`run_vs_oneapi.bat <deck0> <deck1>`。
只重建 SDK：`build_sdk.bat /FORCE`。

---

## 9. 与 PDF 那份文档的关系

`..\Stone_mode\响应文件0825-1(1).pdf`（以及 `openSource_soft\vs_environment\` 下的同一份）
是这条路线的方法来源。注意该 PDF 的**中文字体没有可用的 ToUnicode 映射**，
`pdftotext` 只能提取到英文和数字；如需全文需先渲染成图再 OCR
（本机有 Tesseract 5.3 + `chi_sim`，但没有 poppler/ghostscript 渲染器）。

本文档记录的是**实际跑通的实现**，与 PDF 的差异以上表为准。
