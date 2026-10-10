# ============================================================================
#  Project-local mirror of  <Tools>/userlib_sdk/source/CMakeLists.txt
# ----------------------------------------------------------------------------
#  Why this file exists
#  --------------------
#  The userlib_sdk ships no prebuilt library: libraduser_win64_gfortran.a and
#  the *.mod files must be built from source/ before any user library can link.
#  The official recipe is Tools/userlib_sdk/build_windows.bat, but it writes its
#  build tree AND its products into the Tools repository.  This mirror runs the
#  same build out-of-tree, so every product lands under Stone_mode/build_local/,
#  and the Tools copy stays exactly as it was shipped.
#
#  The single intentional deviation from the official recipe
#  ----------------------------------------------------------
#  GCC 14 promoted -Wimplicit-function-declaration from a warning to an ERROR,
#  and source/interface_routines/win64_gfortran_wrapper.c relies on implicitly
#  declared Fortran entry points (all of them SUBROUTINEs, i.e. void, so the
#  implicit 'int' return type was always harmless).  One flag is appended to
#  the C flags below.  Nothing else differs: the source globs, the include
#  search path, and the Fortran flags are all taken from the official files.
#
#  Two intentional deviations, both driven by -Dcompiler=
#  ------------------------------------------------------
#  1. Implicit function declarations.  win64_gfortran_wrapper.c calls every
#     Fortran entry point without a prototype in scope.  GCC 14 promoted that
#     from a warning to an error, and icx inherited the same hard error from
#     clang.  One flag on the C side silences it for either compiler.
#
#  2. compiler=oneapi only - the wrapper is invisible to icx.  The SDK ships
#     exactly one wrapper source and its whole body sits inside
#     "#ifdef _WIN64 / #ifdef __GNUC__".  icx never defines __GNUC__ (checked
#     in clang-cl, icx-cl and "icx -x c" driver modes), so it compiles to a
#     674-byte object containing none of ST_LECM99 / ENG_SIGEPS99 / ... - the
#     13 entry points dyn_userlib.c GetProcAddress-es, every one of which must
#     resolve or the solver reports ERROR 1130 on /MAT/USER01.  Rather than
#     fork 691 lines, this file generates a copy with that single gate opened.
#     Two further mismatches in the shipped oneapi config are corrected here:
#     ifx needs /names:lowercase, and the target needs an explicit "lib"
#     prefix (see the notes at those lines).
#
#  Configuration variables (pass with -D on the cmake command line)
#  ---------------------------------------------------------------
#    SDK_SOURCE  path to <Tools>/userlib_sdk/source      (required)
#    arch        win64                                   (default win64)
#    compiler    gfortran | oneapi                       (default gfortran)
#    precision   dp | sp                                 (default dp)
# ============================================================================

cmake_minimum_required (VERSION 3.5)
project (stone_raduser_sdk)

enable_language (Fortran)
enable_language (C)

set(CMAKE_C_OUTPUT_EXTENSION_REPLACE 1)
set(CMAKE_Fortran_OUTPUT_EXTENSION_REPLACE 1)

if (NOT DEFINED arch)
  set (arch "win64")
endif()
if (NOT DEFINED compiler)
  set (compiler "gfortran")
endif()
if (NOT DEFINED precision)
  set (precision "dp")
endif()

if (NOT DEFINED SDK_SOURCE)
  message (FATAL_ERROR "SDK_SOURCE is not set. Pass -DSDK_SOURCE=<path to Tools>/userlib_sdk/source")
endif()
get_filename_component (source_directory "${SDK_SOURCE}" ABSOLUTE)
if (NOT EXISTS "${source_directory}/CMakeLists.txt")
  message (FATAL_ERROR "SDK_SOURCE does not look like userlib_sdk/source: ${source_directory}")
endif()

# Load the official compiler settings.  This is the same file the SDK's own
# CMakeLists includes; it defines Fortran_Compiler_flags and C_Compiler_flags.
include ("${source_directory}/Cmake_Compilers/cmake_${arch}_${compiler}.txt")

# --- deviations 1 and 2: see the header comment ------------------------------
# Verified to work verbatim with both gcc 15.2 and icx 2026.1.  Note that icx
# wants the -W spelling; the Intel-style /Qdiag-disable is silently ignored in
# clang-cl mode, so keep this flag as-is.
set (C_Compiler_flags "${C_Compiler_flags} -Wno-implicit-function-declaration")

if (compiler STREQUAL "oneapi")
  # ifx decorates external names in UPPERCASE by default.  The wrapper calls
  # them in lowercase, and gfortran gets that for free from -fno-underscoring,
  # which has no counterpart in cmake_win64_oneapi.txt.  Without this the link
  # fails with unresolved st_lecm99 / eng_sigeps99 / ... at every entry point.
  set (Fortran_Compiler_flags "${Fortran_Compiler_flags} /names:lowercase")
endif()
# -----------------------------------------------------------------------------

set (include_directory "${source_directory}/includes")

file(GLOB_RECURSE include_files ${source_directory}/*.h  ${source_directory}/*.inc)
set (include_dir_list "")
foreach (incfile ${include_files})
    get_filename_component(dir ${incfile} PATH)
    list (APPEND include_dir_list ${dir})
endforeach()
list(REMOVE_DUPLICATES include_dir_list)

# C sources: the SDK's own, plus the userlib_routines ones, minus the engine
# initialization callbacks (those are compiled into the solver, not the DLL).
file(GLOB_RECURSE c_source_files ${source_directory}/*.c ${source_directory}/../userlib_routines/*.c)
file(GLOB_RECURSE c_source_files_remove ${source_directory}/../userlib_routines/engine/initialization/*.c)
list(REMOVE_ITEM c_source_files ${c_source_files_remove})

# deviation 2: swap the SDK's gfortran-only wrapper for a generated copy whose
# __GNUC__ gate is opened.  "#if 1" rather than a deleted line keeps the file's
# #if / #endif pairs balanced - the matching #endif is the last line but one.
if (compiler STREQUAL "oneapi")
  set (_wrapper_in  "${source_directory}/interface_routines/win64_gfortran_wrapper.c")
  set (_wrapper_out "${CMAKE_CURRENT_BINARY_DIR}/win64_oneapi_wrapper.c")
  if (NOT EXISTS "${_wrapper_in}")
    message (FATAL_ERROR "SDK wrapper not found: ${_wrapper_in}")
  endif()
  file (READ "${_wrapper_in}" _wrapper_src)
  string (REPLACE "#ifdef __GNUC__"
                  "#if 1 /* gate opened for oneapi: icx does not define __GNUC__ */"
                  _wrapper_src "${_wrapper_src}")
  file (WRITE "${_wrapper_out}" "${_wrapper_src}")
  list (REMOVE_ITEM c_source_files "${_wrapper_in}")
  list (APPEND c_source_files "${_wrapper_out}")
  message (STATUS "  oneapi wrapper generated: ${_wrapper_out}")
endif()

# Fortran sources.  Only uppercase *.F is compiled - the lowercase *.f files
# under userlib_routines/ are the *user's* routines, compiled later by
# build_userlib.bat, and must not be baked into this archive.
file(GLOB_RECURSE fortran_source_files ${source_directory}/*.F ${source_directory}/../userlib_routines/*.F)
file(GLOB_RECURSE f_source_files_remove ${source_directory}/../userlib_routines/engine/initialization/*.F)
list(REMOVE_ITEM fortran_source_files ${f_source_files_remove})

# The official CMakeLists clears every global flag, keeping all compiler
# options in the two per-source COMPILE_FLAGS properties instead.
set (CMAKE_Fortran_FLAGS " " )
set (CMAKE_C_FLAGS " " )
set (CMAKE_CPP_FLAGS " " )
set (CMAKE_CXX_FLAGS " " )
set (CMAKE_Fortran_FLAGS_DEBUG " " )
set (CMAKE_Fortran_FLAGS_RELEASE " " )
set (CMAKE_C_FLAGS_DEBUG " " )
set (CMAKE_C_FLAGS_RELEASE " " )
set (CMAKE_CPP_FLAGS_DEBUG " " )
set (CMAKE_CPP_FLAGS_RELEASE " " )
set (CMAKE_CXX_FLAGS_DEBUG " " )
set (CMAKE_CXX_FLAGS_RELEASE " " )

set_source_files_properties( ${fortran_source_files} PROPERTIES COMPILE_FLAGS "${Fortran_Compiler_flags}")
set_source_files_properties( ${c_source_files}       PROPERTIES COMPILE_FLAGS "${C_Compiler_flags}")

set (_target "raduser_${arch}${lib_prec}_${compiler}")
add_library(${_target} STATIC ${c_source_files} ${fortran_source_files})

# build_userlib.bat looks for  <RAD_USERLIB_SDK_PATH>\<RAD_USERLIB_ARCH>\
# libraduser_win64<lib_prec>_<compiler>.<ext>, so the "lib" prefix must be
# explicit.  CMake's GNU platform module adds it on its own, but an ifx/icx
# build selects the MSVC module, which does not - the archive would come out as
# raduser_win64_oneapi.lib and the build script would not find it.
set_target_properties(${_target} PROPERTIES PREFIX "lib")

target_include_directories(${_target} PRIVATE ${include_dir_list})

message (STATUS " ")
message (STATUS "OpenRadioss userlib_sdk (mirrored build)")
message (STATUS "  SDK source : ${source_directory}")
message (STATUS "  arch       : ${arch}   compiler: ${compiler}   precision: ${precision}")
message (STATUS "  Fortran    : ${CMAKE_Fortran_COMPILER}   C: ${CMAKE_C_COMPILER}")
message (STATUS "  target     : lib${_target}")
message (STATUS " ")
list(LENGTH fortran_source_files _nF)
list(LENGTH c_source_files _nC)
message (STATUS "  ${_nF} Fortran + ${_nC} C source files")
message (STATUS " ")
