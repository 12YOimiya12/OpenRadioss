# Project-local mirror of Tools/userlib_sdk/source/CMakeLists.txt for oneAPI.
# The SDK source tree remains outside this repository and is never modified.

cmake_minimum_required(VERSION 3.5)
project(openradioss_userlib_sdk LANGUAGES C Fortran)

if(NOT DEFINED arch)
  set(arch win64)
endif()
if(NOT DEFINED compiler)
  set(compiler oneapi)
endif()
if(NOT DEFINED precision)
  set(precision dp)
endif()
if(NOT DEFINED SDK_SOURCE)
  message(FATAL_ERROR "SDK_SOURCE must point to Tools/userlib_sdk/source")
endif()

get_filename_component(source_directory "${SDK_SOURCE}" ABSOLUTE)
if(NOT EXISTS "${source_directory}/CMakeLists.txt")
  message(FATAL_ERROR "Invalid SDK source directory: ${source_directory}")
endif()

include("${source_directory}/Cmake_Compilers/cmake_${arch}_${compiler}.txt")

# Why the C dispatch shim is NOT built here
# -----------------------------------------
# The SDK also ships source/interface_routines/win64_gfortran_wrapper.c, a C
# shim that publishes the ABI names (ST_LECG, ENG_SIGEPS99, ...). GCC needs it,
# because the SDK's Fortran keeps both its !DEC$ ATTRIBUTES DLLEXPORT directives
# and their ALIAS names inside "#ifdef _WIN64", and gfortran never defines
# _WIN64 - so for GCC those lines are dead comments and the shim is the only way
# to get the names exported.
#
# ifx inverts the picture. Under /fpp it does define _WIN64, so for Intel:
#   * the interface routines are pinned to UPPERCASE external names by
#         ALIAS : "ST_LECG" :: ST_LECG
#     and
#   * DLLEXPORT is live, so each object carries /EXPORT:ST_LECG in .drectve and
#     exports itself.
# Both of those are exactly what engine|starter source/user_interface/dyn_userlib.c
# looks up under its own #ifdef _WIN64. Building the shim as well is not merely
# redundant, it is the bug: the shim calls the dispatchers in lowercase, and the
# MSVC linker is case-sensitive, so every one of those calls comes back
# "unresolved external symbol st_lecg". This mirror therefore drops the shim
# rather than trying to repair it.

file(GLOB_RECURSE c_source_files
  "${source_directory}/*.c"
  "${source_directory}/../userlib_routines/*.c")
file(GLOB_RECURSE c_source_files_remove
  "${source_directory}/../userlib_routines/engine/initialization/*.c")
list(REMOVE_ITEM c_source_files ${c_source_files_remove})

# Keep the GCC-only shim out of the archive. Under icx it would compile to a
# 674-byte empty object anyway (its whole body is behind #ifdef __GNUC__, which
# icx does not define), but leaving it in only invites confusion.
list(REMOVE_ITEM c_source_files
  "${source_directory}/interface_routines/win64_gfortran_wrapper.c")

file(GLOB_RECURSE fortran_source_files
  "${source_directory}/*.F"
  "${source_directory}/../userlib_routines/*.F")
file(GLOB_RECURSE f_source_files_remove
  "${source_directory}/../userlib_routines/engine/initialization/*.F")
list(REMOVE_ITEM fortran_source_files ${f_source_files_remove})

# Keep flags on each source as the official SDK project does. The GCC-only
# shim has legacy implicit C declarations; clang-style icx requires this
# diagnostic to be downgraded whenever that file is compiled.
set(CMAKE_Fortran_FLAGS "")
set(CMAKE_C_FLAGS "")
set(CMAKE_Fortran_FLAGS_DEBUG "")
set(CMAKE_Fortran_FLAGS_RELEASE "")
set(CMAKE_C_FLAGS_DEBUG "")
set(CMAKE_C_FLAGS_RELEASE "")
# /names:lowercase /assume:nounderscore makes every external name that is not
# ALIAS-pinned look exactly like it does in the gfortran build (which passes
# -fno-underscoring): lowercase, no trailing underscore. Everything else in the
# SDK assumes that spelling:
#   * source/interface_routines/init_callback.c defines ARRET, arret, userlib_id
#     and set_callback - the trailing underscore is on none of them, so a
#     /assume:underscore build leaves every "CALL ARRET" unresolved;
#   * the dispatch routines reach the user routines as lecmuser99 / luser99.
# /assume:underscore was the original setting here and is what broke the link.
set(Fortran_Compiler_flags "${Fortran_Compiler_flags} /names:lowercase /assume:nounderscore")
set(C_Compiler_flags "${C_Compiler_flags} -Wno-implicit-function-declaration")

set_source_files_properties(${fortran_source_files}
  PROPERTIES COMPILE_FLAGS "${Fortran_Compiler_flags}")
set_source_files_properties(${c_source_files}
  PROPERTIES COMPILE_FLAGS "${C_Compiler_flags}")

file(GLOB_RECURSE include_files
  "${source_directory}/*.h"
  "${source_directory}/*.inc")
set(include_dir_list "")
foreach(incfile ${include_files})
  get_filename_component(incdir "${incfile}" PATH)
  list(APPEND include_dir_list "${incdir}")
endforeach()
list(REMOVE_DUPLICATES include_dir_list)

set(target_name "raduser_${arch}${lib_prec}_${compiler}")
add_library(${target_name} STATIC ${c_source_files} ${fortran_source_files})
target_include_directories(${target_name} PRIVATE ${include_dir_list})

# The SDK build_userlib.bat expects libraduser_win64_oneapi.lib. The MSVC
# CMake platform does not add the GNU-style lib prefix automatically.
set_target_properties(${target_name} PROPERTIES PREFIX "lib")

list(LENGTH fortran_source_files fortran_count)
list(LENGTH c_source_files c_count)
message(STATUS "OpenRadioss userlib SDK oneAPI configuration")
message(STATUS "  SDK source : ${source_directory}")
message(STATUS "  arch       : ${arch}")
message(STATUS "  compiler   : ${compiler}")
message(STATUS "  precision  : ${precision}")
message(STATUS "  Fortran    : ${CMAKE_Fortran_COMPILER}")
message(STATUS "  C          : ${CMAKE_C_COMPILER}")
message(STATUS "  sources    : ${fortran_count} Fortran + ${c_count} C")
