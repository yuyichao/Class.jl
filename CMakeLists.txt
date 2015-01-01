project(Class.jl NONE)

## Setup
cmake_minimum_required(VERSION 2.8)
set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}"
  "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

include(JuliaMacros)
include(CMakePathMacros)

julia_site_path(julia_path)
enable_testing()

add_subdirectory(src)
add_subdirectory(test)
