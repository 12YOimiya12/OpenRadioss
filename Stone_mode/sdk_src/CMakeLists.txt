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
#  Configuration variables (pass with -D on the cmake command line)
#  ---------------------------------------------------------------
#    SDK_SOURCE  path to <Tools>/userlib_sdk/source      (required)
#    arch        win64                                   (default win64)
#    compiler    gfortran                                (default gfortran)
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

# --- the one deviation: see the header comment -------------------------------
set (C_Compiler_flags "${C_Compiler_flags} -Wno-implicit-function-declaration")
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

add_library(raduser_win64_gfortran STATIC ${c_source_files} ${fortran_source_files})
target_include_directories(raduser_win64_gfortran PRIVATE ${include_dir_list})

message (STATUS " ")
message (STATUS "OpenRadioss userlib_sdk (mirrored build)")
message (STATUS "  SDK source : ${source_directory}")
message (STATUS "  arch       : ${arch}   compiler: ${compiler}   precision: ${precision}")
message (STATUS "  Fortran    : ${CMAKE_Fortran_COMPILER}   C: ${CMAKE_C_COMPILER}")
message (STATUS "  .F files   : ${fortran_source_files}")
message (STATUS " ")
list(LENGTH fortran_source_files _nF)
list(LENGTH c_source_files _nC)
message (STATUS "  ${_nF} Fortran + ${_nC} C source files")
message (STATUS " ")
