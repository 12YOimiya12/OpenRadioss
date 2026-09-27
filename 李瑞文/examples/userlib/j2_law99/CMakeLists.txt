cmake_minimum_required(VERSION 3.16)

project(raduser_j2_law99 C)

option(OPENRADIOSS_USERLIB_SINGLE_PRECISION "Build a MYREAL4 user library" OFF)

add_library(raduser_j2_law99 SHARED raduser_j2_law99.c)

target_compile_features(raduser_j2_law99 PRIVATE c_std_99)

if(OPENRADIOSS_USERLIB_SINGLE_PRECISION)
  target_compile_definitions(raduser_j2_law99 PRIVATE MYREAL4)
  if(WIN32)
    set(_raduser_output libraduser_win64_sp)
  else()
    set(_raduser_output raduser_linux64_sp)
  endif()
else()
  target_compile_definitions(raduser_j2_law99 PRIVATE MYREAL8)
  if(WIN32)
    set(_raduser_output libraduser_win64)
  else()
    set(_raduser_output raduser_linux64)
  endif()
endif()

set_target_properties(raduser_j2_law99 PROPERTIES OUTPUT_NAME "${_raduser_output}")

if(WIN32)
  set_target_properties(raduser_j2_law99 PROPERTIES PREFIX "")
else()
  target_link_libraries(raduser_j2_law99 PRIVATE m)
endif()

