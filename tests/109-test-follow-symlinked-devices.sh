source $SRCDIR/libtest.sh

test_follow_symlinked_devices() {
  local devs dev
  local devlinks devlink
  local test_status=1
  local testname=`basename "$0"`
  local vg_name="css-test-foo"
  local infile=${WORKDIR}/container-storage-setup
  local outfile=${WORKDIR}/container-storage
  local config_name="css-test-config"

  # Create a symlink for a device and try to follow it
  for dev in $TEST_DEVS; do
    if [ ! -h $dev ]; then
      devlink="/tmp/$(basename $dev)-test.$$"
      ln -s $dev $devlink

      dev=$devlink
      devlinks="$devlinks $dev"
    fi
    devs="$devs $dev"
    echo "Using symlinke devices: $dev -> $(readlink -e $dev)" >> $LOGS
  done

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
    cleanup_soft_links "$devlinks"
    cleanup $vg_name "$TEST_DEVS" "$infile" "$outfile" "$config_name"
    return $test_status
  fi

  # Make sure volume group $VG got created.
  if vg_exists "$vg_name"; then
    test_status=0
  else
    echo "ERROR: $testname: $CSSBIN failed. $vg_name was not created." >> $LOGS
  fi

  cleanup_soft_links "$devlinks"
  cleanup $vg_name "$TEST_DEVS" "$infile" "$outfile" "$config_name"
  return $test_status
}

# Make sure symlinked disk names are supported.
test_follow_symlinked_devices
