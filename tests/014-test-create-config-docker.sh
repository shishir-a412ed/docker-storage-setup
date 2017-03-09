source $SRCDIR/libtest.sh

# Test creation of default (docker) config.
# Returns 0 on success and 1 on failure.
test_docker_config() {
  local devs=$TEST_DEVS
  local test_status=1
  local testname=`basename "$0"`
  local vg_name="css-test-foo"
  local infile="/etc/sysconfig/docker-storage-setup"
  local outfile="/etc/sysconfig/docker-storage"
  local default_config_name="docker"

  # Error out if any pre-existing volume group vg named css-test-foo
  if vg_exists "$vg_name"; then
    echo "ERROR: $testname: Volume group $vg_name already exists." >> $LOGS
    return $test_status
  fi

  # Create config file
  cat << EOF > $infile
DEVS="$devs"
VG=$vg_name
EOF

 # Run container-storage-setup
 $CSSBIN >> $LOGS 2>&1

 # Test failed.
 if [ $? -ne 0 ]; then
    echo "ERROR: $testname: $CSSBIN failed." >> $LOGS
    cleanup $vg_name "$devs" "$infile" "$outfile" "$default_config_name"
    return $test_status
 fi

  # Make sure configuration $default_config_name was created successfully.
  if config_exists "$default_config_name"; then
    test_status=0
  else
    echo "ERROR: $testname: $CSSBIN failed. Configuration $default_config_name was not created." >> $LOGS
  fi

  cleanup $vg_name "$devs" "$infile" "$outfile" "$default_config_name"
  return $test_status
}

test_docker_config
