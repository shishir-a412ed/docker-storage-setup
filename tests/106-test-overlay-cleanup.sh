source $SRCDIR/libtest.sh

# Test "container-storage-setup --reset". Returns 0 on success and 1 on failure.
test_reset_overlay() {
  local test_status=0
  local testname=`basename "$0"`
  local infile=${WORKDIR}/container-storage-setup
  local outfile=${WORKDIR}/container-storage
  local config_dir="/var/lib/container-storage-setup"
  local config_name="css-test-config"
  local metadata_dir=${config_dir}/${config_name}

  cat << EOF > $infile
STORAGE_DRIVER=overlay
CONFIG_NAME=$config_name
EOF

 # Run container-storage-setup
 $CSSBIN $infile $outfile >> $LOGS 2>&1

 # Test failed.
 if [ $? -ne 0 ]; then
    echo "ERROR: $testname: $CSSBIN failed." >> $LOGS
    rm -f $infile $outfile
    rm -rf "$metadata_dir"
    return 1
 fi

 $CSSBIN --reset $infile $outfile >> $LOGS 2>&1
 if [ $? -ne 0 ]; then
    # Test failed.
    echo "ERROR: $testname: $CSSBIN --reset failed." >> $LOGS
    test_status=1
 elif [ -e $outfile ]; then
    # Test failed.
    echo "ERROR: $testname: $CSSBIN --reset $infile $outfile failed to remove $outfile." >> $LOGS
    test_status=1
 fi

 rm -f $infile $outfile
 rm -rf "$metadata_dir"
 return $test_status
}

# Create a overlay backend and then make sure the
# container-storage-setup --reset
# cleans it up properly.
test_reset_overlay
