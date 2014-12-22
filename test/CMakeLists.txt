#
enable_testing()

add_test(test-class
  env "JULIA_LOAD_PATH=${PROJECT_SOURCE_DIR}/src" julia
  "${CMAKE_CURRENT_SOURCE_DIR}/test-class.jl")

add_test(test-chain
  env "JULIA_LOAD_PATH=${PROJECT_SOURCE_DIR}/src" julia
  "${CMAKE_CURRENT_SOURCE_DIR}/test-chain.jl")
