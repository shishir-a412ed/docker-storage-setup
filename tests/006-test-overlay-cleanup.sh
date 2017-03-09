source $SRCDIR/libtest.sh

# Test "container-storage-setup --reset". Returns 0 on success and 1 on failure.
test_reset_overlay() {
  local test_status=0
  local testname=`basename "$0"`
  local infile=/etc/sysconfig/docker-storage-setup
  local outfile=/etc/sysconfig/docker-storage
  local config_dir="/var/lib/container-storage-setup"
  local default_config_name="docker"
  local metadata_dir="$config_dir"/"$default_config_name"

  cat << EOF > ${infile}
STORAGE_DRIVER=overlay
EOF

 # Run container-storage-setup
 $CSSBIN >> $LOGS 2>&1

 # Test failed.
 if [ $? -ne 0 ]; then
    echo "ERROR: $testname: $CSSBIN failed." >> $LOGS
    rm -f $infile $outfile
    rm -rf $metadata_dir
    return 1
 fi

 $CSSBIN --reset >> $LOGS 2>&1
 if [ $? -ne 0 ]; then
    # Test failed.
    echo "ERROR: $testname: $CSSBIN --reset failed." >> $LOGS
    test_status=1
 elif [ -e /etc/sysconfig/docker-storage ]; then
    # Test failed.
    echo "ERROR: $testname: $CSSBIN --reset failed to cleanup $outfile." >> $LOGS
    test_status=1
 fi

 rm -f $infile $outfile
 rm -rf $metadata_dir
 return $test_status
}

# Create a overlay backend and then make sure the
# container-storage-setup --reset
# cleans it up properly.
test_reset_overlay
