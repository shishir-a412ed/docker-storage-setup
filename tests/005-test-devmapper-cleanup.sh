source $SRCDIR/libtest.sh

# Test "container-storage-setup reset". Returns 0 on success and 1 on failure.
test_reset_devmapper() {
  local devs=${TEST_DEVS}
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

  $CSSBIN --reset >> $LOGS 2>&1
  # Test failed.
  if [ $? -eq 0 ]; then
     if [ -e /etc/sysconfig/docker-storage ]; then
	 echo "ERROR: $testname: $CSSBIN failed. /etc/sysconfig/docker-storage still exists." >> $LOGS
     else
	 if lv_exists $vg_name "docker-pool"; then
	     echo "ERROR: $testname: Thin pool docker-pool still exists." >> $LOGS
	 else
	     test_status=0
	 fi
     fi
  fi

  if [ $test_status -ne 0 ]; then
      echo "ERROR: $testname: $CSSBIN --reset failed." >> $LOGS
  fi

  cleanup $vg_name "$devs" "$infile" "$outfile" "$default_config_name"

  return $test_status
}

# Create a devicemapper docker backend and then make sure the
# `container-storage-setup --reset`
# cleans it up properly.
test_reset_devmapper
