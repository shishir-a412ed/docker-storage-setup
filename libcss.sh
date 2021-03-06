#!/bin/bash
# Library for common functions

# echo info messages on stdout
Info() {
  # stdout is used to pass back output from bash functions
  #  so we use stderr
  echo "INFO: ${1}" >&2
}

# echo error messages on stderr
Error() {
  echo "ERROR: ${1}" >&2
}

# echo error on stderr and exit with error code 1
Fatal() {
  Error "${1}"
  exit 1
}

# checks the size specifications acceptable to -L
check_numeric_size_syntax() {
  data_size=$1

  # if it is all numeric, it is valid as by default it will be MB.
  [[ $data_size =~ ^[[:digit:]]+$ ]] && return 0

  # Numeric digits followed by b or B. (byte specification)
  [[ $data_size =~ ^[[:digit:]]+[bB]$ ]] && return 0

  # Numeric digits followed by valid suffix. Will support both G and GB.
  [[ $data_size =~ ^[[:digit:]]+[sSkKmMgGtTpPeE][bB]?$ ]] && return 0

  # Numeric digits followed by valid suffix and ib. Ex. Gib or GiB.
  [[ $data_size =~ ^[[:digit:]]+[sSkKmMgGtTpPeE]i[bB]$ ]] && return 0

  return 1
}

check_data_size_syntax() {
  local data_size=$1

  # For -l style options, we only support %FREE and %VG option. %PVS and
  # %ORIGIN does not seem to make much sense for this use case.
  if [[ $data_size == *%FREE ]] || [[ $data_size == *%VG ]];then
    return 0
  fi

  # -L compatible syntax
  check_numeric_size_syntax $data_size && return 0
  return 1
}

# Check if passed in vg exists. Returns 0 if volume group exists.
vg_exists() {
  local vg=$1

  for vg_name in $(vgs --noheadings -o vg_name); do
    if [ "$vg_name" == "$vg" ]; then
      return 0
    fi
  done
  return 1
}

# Remove volume group if it exists
remove_vg_if_exists() {
  vg_exists $1 || return 0
  vgremove "$1" > /dev/null
}

pv_exists() {
  pvs $1 >/dev/null 2>&1
}

remove_pv_if_exists() {
  pv_exists $1 || return 0
  pvremove $1 >/dev/null
}
