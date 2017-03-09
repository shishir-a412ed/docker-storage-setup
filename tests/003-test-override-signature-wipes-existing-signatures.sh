source $SRCDIR/libtest.sh

test_override_signatures() {
  local devs=$TEST_DEVS dev
  local test_status=1
  local testname=`basename "$0"`
  local vg_name="css-test-foo"
  local infile="/etc/sysconfig/docker-storage-setup"
  local outfile="/etc/sysconfig/docker-storage"
  local default_config_name="docker"

  # Error out if vg_name VG exists already
  if vg_exists "$vg_name"; then
    echo "ERROR: $testname: Volume group $vg_name already exists." >> $LOGS
    return $test_status
  fi 

  cat << EOF > $infile
DEVS="$devs"
VG=$vg_name
WIPE_SIGNATURES=true
EOF

  # create lvm signatures on disks
  for dev in $devs; do
    pvcreate -f $dev >> $LOGS 2>&1
  done

  # Run container-storage-setup
  $CSSBIN >> $LOGS 2>&1

  # Test failed.
  if [ $? -ne 0 ]; then
    echo "ERROR: $testname: $CSSBIN failed." >> $LOGS
    cleanup $vg_name "$devs" "$infile" "$outfile" "$default_config_name"
    return $test_status
  fi

  # Make sure volume group $VG got created.
  if vg_exists "$vg_name"; then
    test_status=0
  else
    echo "ERROR: $testname: $CSSBIN failed. $vg_name was not created." >> $LOGS
  fi

  cleanup $vg_name "$devs" "$infile" "$outfile" "$default_config_name"
  return $test_status
}

# Create a disk with some signature, say lvm signature and make sure
# override signature can override that, wipe signature and create thin
# pool.
test_override_signatures
