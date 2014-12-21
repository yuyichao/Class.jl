#

set(Class_SRCS
  Class.jl
  class-utils.jl)

cmake_utils_install_files("${julia_path}/Class/src"
  FILES: ${Class_SRCS})
