#

set(Class_SRCS
  Class.jl
  class-utils.jl)

install(FILES ${Class_SRCS} DESTINATION "${julia_path}/Class/src")
