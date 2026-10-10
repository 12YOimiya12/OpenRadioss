# Stone_mode —— VS2022 + oneAPI 环境配置

本文只讲**环境**：本机 VS2022 + oneAPI 工具链在哪里、怎么一键起、以及要让
`Stone_mode` 走 Intel 路线还差什么。

- 环境排查日期：2026-10-10
- 本轮状态：**环境已配好并验证通过，未编译任何库**（用户指定）
- 一键入口：`check_oneapi_env.bat`（验证环境）；`vs_env.bat`（只设环境）
- 既有 gfortran 路线不受影响，见 `Stone_mode二次开发步骤.md`

---

## 1. 本机工具链位置（两个都是非标准路径）

| 组件 | 路径 | 版本 |
|---|---|---|
| Visual Studio Professional 2022 | `G:\Program Files\visualStudio` | 17.14.41 |
| MSVC 工具集 | `%VS%\VC\Tools\MSVC` | 14.44.35207 |
| Windows SDK | `C:\Program Files (x86)\Windows Kits\10` | 10.0.26100.0 |
| oneAPI | `G:\One_API` | 2026.1.1 |
| ifx / icx | `G:\One_API\compiler\2026.1\bin` | 2026.1.1 |
| MKL | `G:\One_API\mkl` | 2026.1 |
| Intel MPI | `G:\One_API\mpi` | 2021.18 |

> `C:\Program Files (x86)\Intel\oneAPI` 里**只有 Installer**，没有编译器。
> 别去那儿找 ifx。

**这是后面大部分问题的根源**：Visual Studio 不在 `%ProgramFiles%\Microsoft Visual
Studio\2022\<Edition>` 下，而 oneAPI 的 `setvars.bat` 只认那几个标准位置。

---

## 2. 一键脚本

### `vs_env.bat` —— 设置 Intel 环境

```bat
call vs_env.bat            :: 在调用者里设置环境（给别的脚本 call）
vs_env.bat                 :: 独立运行，并打印摘要
vs_env.bat quiet           :: 同上，不打印摘要
vs_env.bat nopause         :: 独立运行结束后不停顿
```

它做四件事：

1. 校验 `KF_VS2022` / `KF_ONEAPI`（可用同名环境变量覆盖，与 `build_sdk.bat` 的
   `KF_MINGW` / `KF_TOOLS` 是同一套约定）；
2. 清掉调用环境里可能残留的 `NoDefaultCurrentDirectoryInExePath`；
3. **设 `VS2022INSTALLDIR`** —— 这是唯一的实质修复；
4. `call "%KF_ONEAPI%\setvars.bat" intel64`，然后校验 `CMPLR_ROOT` 已置位。

`setlocal` 故意没写：被 `call` 时环境必须留在调用者里。

### `check_oneapi_env.bat` —— 验证环境

```bat
check_oneapi_env.bat
```

依次做：设环境 → 查 ifx/icx/link → **用 ifx+icx 对 `sdk_src` 做一次 CMake
configure**（只配置，不编译）→ 检查生成的 oneapi wrapper 是否真的把
`__GNUC__` 门槛打开了、预处理指令配不配对。

配置一遍几秒钟就能把整条工具链（编译器探测、包含路径、wrapper 生成）走通，
而编译 SDK 静态库是约 400 个定长格式 Fortran 文件，所以这里只做 configure。

产物全部落在 `build_local\sdk_build_oneapi\`。

---

## 3. 四个坑（全部实测，不是推测）

### 坑 1：`setvars.bat` 开箱即坏

```
WARNING: Visual Studio was not found in a standard install location
...
'vars.bat' 不是内部或外部命令，也不是可运行的程序或批处理文件     ← 13 次
```

原因：`G:\One_API\compiler\2026.1\env\vars.bat` 里 VS 探测写死了
`%ProgramFiles%\Microsoft Visual Studio\2022\{Professional,Enterprise,Community}`。
找不到 → 它打印警告 → 然后**每个组件的 `vars.bat` 都失败**（文件明明都在）。

修法就一个变量：

```bat
set "VS2022INSTALLDIR=G:\Program Files\visualStudio"
```

因为那个文件里有 `if defined VS2022INSTALLDIR (...)`，设了就不再探测。
实测：设了之后 13 个组件全部初始化，`errorlevel = 0`。

> 附注：还有一个**症状相同、原因完全不同**的坑。`setvars.bat` 是靠
> `pushd <组件>\latest\env` + `call vars.bat`（相对名）工作的，需要当前目录在
> 可执行文件搜索路径里。如果调用环境里设了 `NoDefaultCurrentDirectoryInExePath`，
> 就会出现一模一样的 `'vars.bat' 不是内部或外部命令`。本机注册表里
> （HKLM / HKCU）**都没有**这个变量，正常 cmd 不会踩；但 `vs_env.bat` 里还是
> 防御性地清了一下。

### 坑 2：SDK 只有一个 wrapper，而它是**给 GCC 专用的**（不是缺陷）

> **本节 2026-10-10 晚修正。** 最初写成"SDK 的 oneapi 路线是空的、是真死结"，
> 那个结论是**错的**。事实见下，也已经用一条完整的 DLL 跑通验证。

`Tools\userlib_sdk` 里只有**一个** wrapper：
`source\interface_routines\win64_gfortran_wrapper.c`，函数体整个包在：

```c
#ifdef _WIN64
#ifdef __GNUC__        ← 这道门是对的，不是 bug
```

实测 **icx 在 clang-cl / `icx-cl` / `icx -x c` 三种驱动模式下都不定义 `__GNUC__`**
（用 `#error` 分支法确认）。所以用 icx 编译这个文件得到 674 字节的空 COFF 对象。

**但那不要紧，因为 ifx 路线上根本不该编这个 wrapper。** 关键在于 SDK 的 Fortran 里：

```fortran
      SUBROUTINE ST_LECG(IGTYP,ROOTN,ROOTLEN,NUVAR ,PARGEO)
#ifdef _WIN64
!DEC$ ATTRIBUTES DLLEXPORT, DECORATE, ALIAS : "ST_LECG" :: ST_LECG
#endif
```

| | gfortran | ifx |
|---|---|---|
| `/fpp` 是否定义 `_WIN64` | ❌ 不定义 | ✅ 定义 |
| 上面的指令 | 死代码 | **生效** |
| 接口例程符号 | 小写 `st_lecg`（`-fno-underscoring`） | **大写 `ST_LECG`**（ALIAS 钉死） |
| 谁来导出符号 | 只能靠 C wrapper | **Fortran 自己**：`!DEC$ ATTRIBUTES DLLEXPORT` |

```
dumpbin /directives st_lecg.F.obj     →  /EXPORT:ST_LECG
dumpbin /directives library_id.c.obj  →  /EXPORT:userlib_id
```

而 `starter|engine\source\user_interface\dyn_userlib.c` 在 Windows 分支
（`#ifdef _WIN64`，starter 第 45 行）`GetProcAddress` 找的**就是这批大写名字**。
（`#elif 1` 那条分支才是 Linux 的 `dlsym` + 小写带下划线，两套名字在这个文件里
并存，容易看混。）

**所以在 ifx 路线上再编一个 C wrapper 不但多余，而且正是故障根源**：
它内部按小写 `st_lecg(...)` 调用，而 **MSVC 链接器区分大小写**，永远绑不上大写的
Fortran 符号 → 34 个 `unresolved external symbol`。这个"链接器不分大小写"的假设
在别处也出现过，是错的。

SDK 的 `win64_oneapi\build_userlib.bat` 那句预编译库"坑位"是空的，只是因为官方
不预编译 SDK 静态库（和 gfortran 那边一样，得自己建），并不代表路线不通。

### 坑 3：icx 把隐式函数声明当硬错误（和 GCC 14+ 一样）

`win64_gfortran_wrapper.c` 调用的所有 Fortran 入口都没有原型在作用域里。实测：

```
icx /c implicit_test.c
  → error: call to undeclared function '...'; ISO C99 and later do not
    support implicit function declarations      errorlevel = 1

icx /c implicit_test.c -Wno-implicit-function-declaration
  → errorlevel = 0
```

注意**必须用 `-W` 那个拼写**：Intel 风格的 `/Qdiag-disable:2668` 在 clang-cl 模式下
被静默忽略（只给一句 `unknown argument ignored`），错误照旧。

好消息：这个 flag 和 gfortran 路线用的**完全是同一个**，所以 `sdk_src` 里那行
追加可以无条件保留。

### 坑 4：ifx 的符号名大小写 + 库文件名的 `lib` 前缀

两个 `cmake_win64_gfortran.txt` 里有、而 `cmake_win64_oneapi.txt` 里没有的东西：

| | gfortran | oneapi | 后果 |
|---|---|---|---|
| 外部符号命名 | `-fno-underscoring` → 小写 | 无 → **默认大写** | wrapper 里调的是小写 `st_lecm99`，**不加 `/names:lowercase` 链接直接失败** |
| 静态库前缀 | `lib_suffix ""`，靠 GNU 模块自带 `lib` | `lib_suffix "lib"`，但 MSVC 模块**不加前缀** | 产物会叫 `raduser_win64_oneapi.lib`，而 `build_userlib.bat` 找的是 `libraduser_win64_oneapi.lib` |

实测：不加 `/names:lowercase` → 链接失败；加了 → 通过。

---

## 4. `sdk_src\CMakeLists.txt` 为 oneapi 加的三处

`sdk_src` 是官方 `CMakeLists.txt` 的项目内镜像（不在 Tools 里改任何东西）。
新增全部**只在 `compiler=oneapi` 下生效**，gfortran 路线逐字节等价。

1. **Fortran flag**：oneapi 下追加 `/names:lowercase`（坑 4）。
2. **wrapper 生成**：不复制 691 行源码，而是在 configure 时读出 SDK 那个文件、
   把 `#ifdef __GNUC__` 替成 `#if 1 /* ... */`，写到构建目录再编。
   用 `#if 1` 而不是删掉这行，是为了让文件里的 `#if` / `#endif` 配对数保持平衡
   （配对的 `#endif` 在文件末尾）。这样 SDK 升级时不会分叉。
3. **库名前缀**：`set_target_properties(... PREFIX "lib")`。对 gfortran 来说
   GNU 模块本来就加 `lib`，显式设置结果相同；对 ifx 这是必需的。

---

## 5. 本机实测记录（2026-10-10）

```
Step 0/3  Intel environment        OK  ifx and icx are on PATH
Step 1/3  Preconditions            OK  ninja, SDK source and cmake_win64_oneapi.txt
Step 2/3  CMake configure with ifx + icx   (no compile)
   C compiler        : IntelLLVM 2026.1.1 with MSVC-like command-line  (icx)
   Fortran compiler  : IntelLLVM 2026.1.1 with MSVC-like command-line  (ifx)
   oneapi wrapper generated: build_local\sdk_build_oneapi\win64_oneapi_wrapper.c
   target            : libraduser_win64_oneapi
   400 Fortran + 3 C source files
Step 3/3  wrapper sanity check
   generated : 48759 bytes
   OK  __GNUC__ gate is opened          (第 27 行确为 "#if 1")
   preprocessor: 4 #if blocks, 4 #endif
   OK  balance is even
```

`build.ninja` 里确认产物名就是 `libraduser_win64_oneapi.lib`，
`ST_LECM99` / `ENG_SIGEPS99` / `ST_LECG` 等带 `dllexport` 的入口都在生成的文件里。
（`userlib_id` 和 `set_callback` 不在这里，它们在 `library_id.c` 和
`init_callback.c` 里，各自独立，属正常。）

**回归确认**：改完 `sdk_src\CMakeLists.txt` 后用 gfortran 再 configure 一次，
目标仍是 `libraduser_win64_gfortran`、产物名仍是 `libraduser_win64_gfortran.a`、
`-Wno-implicit-function-declaration` 在位、`/names:lowercase` 没有泄漏进来。
原有路线未受影响。

---

## 6. 状态（2026-10-10 晚）

原先这里列的三条"下一步"，当晚全部做完并跑通了 —— 实现放在**新目录
`VS_OneAPI\`**（不是 `Stone_mode\`），入口脚本 `run_vs_oneapi.bat`。
本节保留为结论记录。

1. **oneapi 静态库已编出**：`VS_OneAPI\build_local\sdk\win64_oneapi\libraduser_win64_oneapi.lib`，
   802 个目标，退出码 0。
2. **用户库 DLL 已编出**：`VS_OneAPI\build_local\userlib_oneapi\libraduser_win64.dll`，
   86 个导出，求解器在 Windows 分支要的 13 + 20 个符号**全在**（`check_exports.bat` 核对）。
3. **不需要重建求解器。** 原猜想得到证实：现有 gfortran 版
   `starter_win64_gf.exe` / `engine_win64_gf.exe` **能直接加载 ifx 编的 DLL**。
   C 边界全是裸指针这一点是关键，两条工具链的运行时各自独立，互不干扰。

**跑通结果**（单砖算例，和 gfortran 路线逐值对比）：

| 产物 | 结果 |
|---|---|
| starter | `0 ERROR(S)`，`kf user01 units: kg, m, s, pa.`，`user01 solid kf concrete law` |
| engine | `NORMAL TERMINATION`，`TOTAL NUMBER OF CYCLES : 15` |
| `stone_kf.h3d` | **逐字节相同** |
| `stone_kfA001..A010` | **逐字节相同**（含末帧 A010） |
| `stone_kfT01` | 仅文件头日期串不同（`Fri Oct 9` vs `Sat Oct 10`），数值载荷逐位相同 |
| 接口版本号 | `2102011231` vs `2102011230` —— `library_id.c` 里 `#ifdef GCC_COMP` 故意区分，属预期 |

**新增的两个坑（跑通前撞到的）：**

- **用户例程的命名约定必须和 SDK 一致。** SDK 的 Fortran 用
  `/names:lowercase /assume:nounderscore`（等价于 gfortran 的 `-fno-underscoring`），
  即小写、**无尾下划线**。调度器按 `lecmuser01` / `luser01` 调用用户例程；
  `ARRET` 由 `source\interface_routines\init_callback.c` 提供，大写小写两个版本都有、
  也都没有尾下划线。用 `/assume:underscore` 编用户源码会得到 `ARRET_`，全数失配。
- **两条工具链的运行时都要进 PATH**，否则求解器在打印任何东西之前就死：
  `_gf` 求解器要 MinGW 运行时（`libgcc_s_seh-1.dll` 等），ifx 编的用户库可能
  在加载期拉 Intel 运行时 DLL。症状是退出码 `0xC0000135`
  （STATUS_DLL_NOT_FOUND）/ `0xC0000139`（STATUS_ENTRYPOINT_NOT_FOUND）。

---

## 7. 文件清单

| 文件 | 说明 |
|---|---|
| `vs_env.bat` | 设置 Intel 环境（设 `VS2022INSTALLDIR` + `call setvars.bat`） |
| `check_oneapi_env.bat` | 验证环境：设环境 + configure `sdk_src` |
| `sdk_src\CMakeLists.txt` | 官方 CMakeLists 的项目内镜像（oneapi 支路） |
| `build_local\sdk_build_oneapi\` | configure 产物 |
| `build_local\envcheck\` | 排查过程的探测脚本与原始证据，可整目录删除 |

**实际的 oneAPI 构建在 `..\VS_OneAPI\`**（本目录只到"环境可用 + SDK 可配置"为止）：
`build_sdk.bat` / `build_userlib.bat` / `check_exports.bat` / `run_vs_oneapi.bat`，
设计说明见那里的 `README.md`。

`.bat` 都是纯 ASCII + CRLF，理由见 `Stone_mode二次开发步骤.md` 坑 5。
**不要从 Git Bash 启动**，用 `cmd` 或 `cmd //c`。

