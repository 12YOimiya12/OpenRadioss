# VS_OneAPI user material build

This folder implements the Windows x64 Intel oneAPI route for the OpenRadioss
Fortran user material interface.

**Step-by-step procedure and the full command list (Chinese):
[`VS_OneAPI二次开发步骤.md`](VS_OneAPI二次开发步骤.md).** That document is the
authoritative walkthrough; what follows is the short version.

The toolchain is Intel oneAPI `ifx` + `icx`, double precision, CMake/Ninja,
and a runtime DLL named `libraduser_win64.dll`. `LECMUSER01.f` is compiled for
Starter and `LUSER01.f` is compiled for Engine.

Prerequisites:

- Visual Studio 2022 with the x64 C/C++ tools;
- Intel oneAPI with `ifx` and `icx`;
- `Tools\userlib_sdk` beside the OpenRadioss repository;
- CMake and the repository Ninja binary;
- an OpenRadioss Windows solver executable. The repository's gfortran build
  (`exec\starter_win64_gf.exe` / `engine_win64_gf.exe`) loads this DLL without
  any problem - verified - so an Intel solver build is not required.

The scripts default to the paths used by this workspace:

```text
Visual Studio: G:\Program Files\visualStudio
oneAPI:       G:\One_API
Tools:        ..\..\Tools
```

Override `KF_VS2022`, `KF_ONEAPI`, `KF_MINGW` or `KF_TOOLS` before running a
script when the installation layout differs.

Build and verify the compiler environment:

```bat
check_env.bat
```

Build the SDK archive and the user DLL:

```bat
build_sdk.bat
build_userlib.bat
check_exports.bat
```

`check_exports.bat` unpacks the DLL's export table and checks it against every
symbol the solver's `source/user_interface/dyn_userlib.c` looks up on Windows.

The products are written below `build_local`:

```text
build_local\sdk\win64_oneapi\libraduser_win64_oneapi.lib
build_local\userlib_oneapi\libraduser_win64.dll
```

Run a calculation with the two input decks:

```bat
run_vs_oneapi.bat path\starter_0000.rad path\engine_0001.rad 4
```

The optional third argument is the Engine thread count. Set
`RAD_STARTER_EXE` and `RAD_ENGINE_EXE` to override the default solver paths;
the script falls back to the repository's `_gf` binaries.

Both toolchains' runtimes must be on `PATH`, or the solver dies with
`0xC0000135` before printing anything: the `_gf` solver needs the MinGW runtime,
and the ifx-built user library may pull in Intel runtime DLLs at load time.
`run_vs_oneapi.bat` sets both.

## Why this route has no C dispatch shim

`userlib_sdk\source\interface_routines\win64_gfortran_wrapper.c` is GCC-only and
its `#ifdef __GNUC__` gate is correct, not a defect.

The SDK's Fortran keeps both its `!DEC$ ATTRIBUTES DLLEXPORT` directives and
their `ALIAS : "ST_LECG" :: ST_LECG` names inside `#ifdef _WIN64`. gfortran never
defines `_WIN64`, so for GCC those lines are dead comments and the shim is the
only way to publish the ABI names to `GetProcAddress`. Under `ifx /fpp`, `_WIN64`
*is* defined, the directives go live, and every interface object exports itself:

```text
dumpbin /directives st_lecg.F.obj     ->  /EXPORT:ST_LECG
dumpbin /directives library_id.c.obj  ->  /EXPORT:userlib_id
```

Those uppercase names are exactly what `source/user_interface/dyn_userlib.c`
looks up in its own `#ifdef _WIN64` branch. Compiling the shim as well cannot
work: it calls the dispatchers in lowercase, and the MSVC linker is
case-sensitive, so `st_lecg` never binds to `ST_LECG` - which is what produced
the original `unresolved external symbol st_lecg` cascade.

Two further points `sdk_src\CMakeLists.txt` depends on:

- `/names:lowercase /assume:nounderscore` puts every non-aliased external name
  in the same spelling GCC produces with `-fno-underscoring`. Everything else in
  the SDK assumes it: the dispatch routines reach user routines as
  `lecmuser01` / `luser01`, and `init_callback.c` defines `ARRET` / `arret` /
  `userlib_id` / `set_callback` with no trailing underscore anywhere.
- `build_userlib.bat` unpacks the archive and then **deletes** the stub objects
  for the routines the user supplies. The archive carries a stub for every law
  number, and with a consistent naming convention the user's `lecmuser01` would
  otherwise collide with the stub's.

The environment script also redirects compiler temporary files to
`build_local\tmp`, which keeps configure and build intermediates inside this
project.
