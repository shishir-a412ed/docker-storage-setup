source $SRCDIR/libtest.sh

# Make sure a disk with lvm signature is rejected and is not overriden
# by css. Returns 0 on success and 1 on failure.
test_lvm_sig() {
  local devs=$TEST_DEVS dev
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

  # create lvm signatures on disks
  for dev in $devs; do
    pvcreate -f $dev >> $LOGS 2>&1
  done

  # Run container-storage-setup
  $CSSBIN >> $LOGS 2>&1

  # Css should fail. If it did not, then test failed. This is very crude
  # check though as css can fail for so many reasons. A more precise check
  # would be too check for exact error message.
  [ $? -ne 0 ] && test_status=0

  cleanup $vg_name "$devs" "$infile" "$outfile" "$default_config_name"
  return $test_status
}

# Make sure a disk with lvm signature is rejected and is not overriden
# by css. Returns 0 on success and 1 on failure.

test_lvm_sig
