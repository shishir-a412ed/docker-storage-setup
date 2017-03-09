source $SRCDIR/libtest.sh

# Test "container-storage-setup reset". Returns 0 on success and 1 on failure.
test_reset_overlay2() {
  local test_status=0
  local testname=`basename "$0"`
  local infile=/etc/sysconfig/docker-storage-setup
  local outfile=/etc/sysconfig/docker-storage
  local config_dir="/var/lib/container-storage-setup"
  local default_config_name="docker"
  local metadata_dir="$config_dir"/"$default_config_name"

  cat << EOF > /etc/sysconfig/docker-storage-setup
STORAGE_DRIVER=overlay2
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

 if ! grep -q "overlay2" /etc/sysconfig/docker-storage; then
    echo "ERROR: $testname: /etc/sysconfig/docker-storage does not have string overlay2." >> $LOGS
    rm -f $infile $outfile
    rm -rf $metadata_dir
    return 1
 fi

 $CSSBIN --reset >> $LOGS 2>&1
 if [ $? -ne 0 ]; then
    # Test failed.
    test_status=1
    echo "ERROR: $testname: $CSSBIN --reset failed." >> $LOGS
 elif [ -e $outfile ]; then
    # Test failed.
    test_status=1
    echo "ERROR: $testname: $CSSBIN $outfile still exists." >> $LOGS
 fi

 rm -f $infile $outfile
 rm -rf $metadata_dir
 return $test_status
}

# Create a overlay2 backend and then make sure the
# container-storage-setup --reset
# cleans it up properly.
test_reset_overlay2
