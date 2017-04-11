source $SRCDIR/libtest.sh

# Make sure a disk with lvm signature is rejected and is not overriden
# by css. Returns 0 on success and 1 on failure.
test_lvm_sig() {
  local devs=$TEST_DEVS dev
  local test_status=1
  local testname=`basename "$0"`
  local vg_name="css-test-foo"
  local tmplog=${WORKDIR}/tmplog
  local errmsg="Wipe signatures using wipefs or use WIPE_SIGNATURES=true and retry."

  # Error out if any pre-existing volume group vg named css-test-foo
  if vg_exists "$vg_name"; then
    echo "ERROR: $testname: Volume group $vg_name already exists." >> $LOGS
    return $test_status
  fi
 
  cat << EOF > /etc/sysconfig/docker-storage-setup
DEVS="$devs"
VG=$vg_name
EOF

  # create lvm signatures on disks
  for dev in $devs; do
    pvcreate -f $dev >> $LOGS 2>&1
  done

  # Run container-storage-setup
  $CSSBIN > $tmplog 2>&1
  rc=$?
  cat $tmplog >> $LOGS 2>&1

  # Test failed.
  if [ $rc -ne 0 ]; then
      if grep --no-messages -q "$errmsg" $tmplog; then
          test_status=0
      else
          echo "ERROR: $testname: $CSSBIN Failed for a reason other then \"$errmsg\"" >> $LOGS
      fi
  else
      echo "ERROR: $testname: $CSSBIN Succeeded. Should have failed since LVM2_member signature exists on devices $devs" >> $LOGS
  fi

  cleanup "$vg_name" "$devs"
  return $test_status
}

# Make sure a disk with lvm signature is rejected and is not overriden
# by css. Returns 0 on success and 1 on failure.

test_lvm_sig
