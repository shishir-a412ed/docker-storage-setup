source $SRCDIR/libtest.sh

# Test creation of custom (container) config.
# Returns 0 on success and 1 on failure.
test_container_config() {
  local devs=$TEST_DEVS
  local test_status=1
  local testname=`basename "$0"`
  local vg_name="css-test-foo"
  local infile=${WORKDIR}/container-storage-setup
  local outfile=${WORKDIR}/container-storage
  local config_name="css-test-config"

  # Error out if any pre-existing volume group vg named css-test-foo
  if vg_exists "$vg_name"; then
    echo "ERROR: $testname: Volume group $vg_name already exists." >> $LOGS
    return $test_status
  fi

  # Create config file
  cat << EOF > $infile
DEVS="$devs"
VG=$vg_name
CONTAINER_THINPOOL=container-thinpool
CONFIG_NAME=$config_name
EOF

 # Run container-storage-setup
 $CSSBIN $infile $outfile >> $LOGS 2>&1

 # Test failed.
 if [ $? -ne 0 ]; then
    echo "ERROR: $testname: $CSSBIN failed." >> $LOGS
    cleanup $vg_name "$devs" "$infile" "$outfile" "$config_name"
    return $test_status
 fi

  # Make sure configuration $config_name was created successfully.
  if config_exists "$config_name"; then
    test_status=0
  else
    echo "ERROR: $testname: $CSSBIN failed. Configuration $config_name was not created." >> $LOGS
  fi

  cleanup $vg_name "$devs" "$infile" "$outfile" "$config_name"
  return $test_status
}

test_container_config
