#!/bin/bash

export WORKDIR=$(pwd)/temp/
METADATA_DIR=/var/lib/docker
export CSSBIN="/usr/bin/container-storage-setup"
export LOGS=$WORKDIR/logs.txt

# Keeps track of overall pass/failure status of tests. Even if single test
# fails, PASS_STATUS will be set to 1 and returned to caller when all
# tests have run.
PASS_STATUS=0

#Helper functions

# Take care of active docker and old docker metadata
check_docker_active() {
  if systemctl -q is-active "docker.service"; then
    echo "ERROR: docker.service is currently active. Please stop docker.service before running tests." >&2
    exit 1
  fi
}

# Check if /var/lib/container-storage-setup is empty or not.
check_css_config_dir(){
  local css_config_dir="/var/lib/container-storage-setup"
  if [[ -d $css_config_dir && "$(ls -A $css_config_dir)" ]];then
     echo "ERROR: directory ${css_config_dir} is not empty." >&2
     exit 1
  fi
}

# Check metadata if using devmapper
check_metadata() {
  local devmapper_meta_dir="$METADATA_DIR/devicemapper/metadata/"
  
  [ ! -d "$devmapper_meta_dir" ] && return 0

  echo "ERROR: ${METADATA_DIR} directory exists and contains old metadata. Remove it." >&2
  exit 1
}

setup_workdir() {
  mkdir -p $WORKDIR
  rm -f $LOGS
}

# If config file is present, error out
check_config_files() {
  if [ -f /etc/sysconfig/docker-storage-setup ];then
    echo "ERROR: /etc/sysconfig/docker-storage-setup already exists. Remove it." >&2
    exit 1
  fi

  if [ -f /etc/sysconfig/docker-storage ];then
    echo "ERROR: /etc/sysconfig/docker-storage already exists. Remove it." >&2
    exit 1
  fi
}

setup_css_binary() {
  # One can setup environment variable CONTAINER_STORAGE_SETUP to override
  # which binary is used for tests.
  if [ -z "$CONTAINER_STORAGE_SETUP" -a -n "$DOCKER_STORAGE_SETUP" ];then
      CONTAINER_STORAGE_SETUP=$DOCKER_STORAGE_SETUP
  fi
  if [ -n "$CONTAINER_STORAGE_SETUP" ];then
    if [ ! -f "$CONTAINER_STORAGE_SETUP" ];then
      echo "Error: Executable $CONTAINER_STORAGE_SETUP does not exist"
      exit 1
    fi

    if [ ! -x "$CONTAINER_STORAGE_SETUP" ];then
      echo "Error: Executable $CONTAINER_STORAGE_SETUP does not have execute permissions."
      exit 1
    fi
    CSSBIN=$CONTAINER_STORAGE_SETUP
  fi
  echo "INFO: Using $CSSBIN for running tests."
}

# If disk already has signatures, error out. It should be a clean disk.
check_disk_signatures() {
  local bdev=$1
  local sig

  if ! sig=$(wipefs -p $bdev); then
    echo "ERROR: Failed to check signatures on device $bdev" >&2
    exit 1
  fi

  [ "$sig" == "" ] && return 0

  while IFS=, read offset uuid label type; do
    [ "$offset" == "# offset" ] && continue

    echo "ERROR: Found $type signature on device ${bdev} at offset ${offset}. Wipe signatures using wipefs and retry."
    exit 1
  done <<< "$sig"
}

#Tests

check_block_devs() {
  local devs=$1

  if [ -z "$devs" ];then
    echo "ERROR: A block device need to be specified for testing in css-test-config file."
    exit 1
  fi

  for dev in $devs; do
    if [ ! -b $dev ];then
      echo "ERROR: $dev is not a valid block device."
      exit 1
    fi

    # Make sure device is not a partition.
    if [[ $dev =~ .*[0-9]$ ]]; then
      echo "ERROR: Partition specification unsupported at this time."
      exit 1
    fi

    check_disk_signatures $dev
  done
}

run_test () {
  testfile=$1

  echo "Running test $testfile" >> $LOGS 2>&1
  bash -c $testfile

  if [ $? -eq 0 ];then
    echo "PASS: $(basename $testfile)"
  else
    echo "FAIL: $(basename $testfile)"
    PASS_STATUS=1
  fi
}

run_tests() {
  if [ $# -gt 0 ]; then
    local files=$@
  else
    local files="$SRCDIR/[0-9][0-9][0-9]-test-*"
  fi
  for t in $files;do
    run_test ./$t
  done
}

#Main Script

# Source config file
export SRCDIR=`dirname $0`
if [ -e $SRCDIR/css-test-config ]; then
  source $SRCDIR/css-test-config
  # DEVS is used by css as well. So exporting this can fail any tests which
  # don't want to use DEVS. So export TEST_DEVS instead.
  TEST_DEVS=$DEVS
  export TEST_DEVS
fi

source $SRCDIR/libtest.sh

usage() {
  cat <<-FOE
    Usage: $1 [OPTIONS] [ test1, test2, ... ]

    Run Container Storage tests

    If you specify no tests to run, all tests will run.

    Options:
      --help    Print help message
FOE
}

if [ $# -gt 0 ]; then
    if [ "$1" == "--help" ]; then
	usage $(basename $0)
	exit 0
    fi
fi

check_docker_active
check_metadata
check_css_config_dir
check_config_files
setup_workdir
setup_css_binary
check_block_devs "$DEVS"
run_tests $@
exit $PASS_STATUS
