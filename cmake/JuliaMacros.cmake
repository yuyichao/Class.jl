#

function(julia_site_path var)
  if(ARGC GREATER 1)
    set(prefix "${ARGV1}")
  else()
    set(prefix "")
  endif()
  set(julia_command "print(((pre) -> filter(((x) -> x[1:length(pre)] == pre), sort(LOAD_PATH, lt=(x, y) -> length(x) < length(y)))[1])(ARGS[1]))")
  execute_process(COMMAND julia -e "${julia_command}" "${prefix}"
    OUTPUT_VARIABLE res)
  set("${var}" "${res}" PARENT_SCOPE)
endfunction()
