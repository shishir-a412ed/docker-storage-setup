source $SRCDIR/libtest.sh

# If CONFIG_NAME is not set, when using options $infile and $outfile.
# container-storage-setup should error out.
test_fail_if_no_config_name(){
  local devs=$TEST_DEVS
  local test_status=1
  local testname=`basename "$0"`
  local vg_name="css-test-foo"
  local infile=${WORKDIR}/container-storage-setup
  local outfile=${WORKDIR}/container-storage
  local errmsg="Specify a storage configuration name using CONFIG_NAME"
  local tmplog=${WORKDIR}/tmplog

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
EOF

  # Run container-storage-setup
  $CSSBIN $infile $outfile > $tmplog 2>&1
  rc=$?
  cat $tmplog >> $LOGS 2>&1

  # Test failed.
  if [ $rc -ne 0 ]; then
     if grep --no-messages -q "$errmsg" $tmplog; then
        test_status=0
     else
        echo "ERROR: $testname: $CSSBIN Failed for a reason other than \"$errmsg\"" >> $LOGS
     fi
  else
     echo "ERROR: $testname: $CSSBIN Succeeded. Should have failed with no CONFIG_NAME specified" >> $LOGS
  fi
  cleanup $vg_name "$devs" "$infile" "$outfile"
  return $test_status
}

test_fail_if_no_config_name
