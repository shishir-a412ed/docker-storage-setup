source $SRCDIR/libtest.sh

# Test CONTAINER_ROOT_LV_NAME and CONTAINER_ROOT_LV_MOUNT_PATH directives.
# Returns 0 on success and 1 on failure.
test_container_root_volume() {
  local devs=$TEST_DEVS
  local test_status=1
  local testname=`basename "$0"`
  local vg_name="css-test-foo"
  local root_lv_name="container-root-lv"
  local root_lv_mount_path="/var/lib/containers"
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
CONTAINER_ROOT_LV_NAME=$root_lv_name
CONTAINER_ROOT_LV_MOUNT_PATH=$root_lv_mount_path
CONTAINER_THINPOOL=container-thinpool
CONFIG_NAME=$config_name
EOF

 # Run container-storage-setup
 $CSSBIN $infile $outfile >> $LOGS 2>&1

 # Test failed.
 if [ $? -ne 0 ]; then
    echo "ERROR: $testname: $CSSBIN failed." >> $LOGS
    cleanup_all $vg_name $root_lv_name $root_lv_mount_path "$devs" $infile $outfile $config_name
    return $test_status
 fi

  # Make sure $CONTAINER_ROOT_LV_NAME {container-root-lv} got created
  # successfully.
  if ! lv_exists "$vg_name" "$root_lv_name"; then
    echo "ERROR: $testname: Logical Volume $root_lv_name does not exist." >> $LOGS
    cleanup_all $vg_name $root_lv_name $root_lv_mount_path "$devs" $infile $outfile
    return $test_status
  fi

  # Make sure $CONTAINER_ROOT_LV_NAME {container-root-lv} is
  # mounted on $CONTAINER_ROOT_LV_MOUNT_PATH {/var/lib/containers}
  local mnt
  mnt=$(findmnt -n -o TARGET --first-only --source /dev/${vg_name}/${root_lv_name})
  if [ "$mnt" != "$root_lv_mount_path" ];then
   echo "ERROR: $testname: Logical Volume $root_lv_name is not mounted on $root_lv_mount_path." >> $LOGS
   cleanup_all $vg_name $root_lv_name $root_lv_mount_path "$devs" $infile $outfile $config_name
   return $test_status
  fi

  cleanup_all $vg_name $root_lv_name $root_lv_mount_path "$devs" $infile $outfile $config_name
  return 0
}

cleanup_all(){
  local vg_name=$1
  local lv_name=$2
  local mount_path=$3
  local devs=$4
  local infile=$5
  local outfile=$6
  local config_name=$7

  umount $mount_path >> $LOGS 2>&1
  lvchange -an $vg_name/${lv_name} >> $LOGS 2>&1
  lvremove $vg_name/${lv_name} >> $LOGS 2>&1

  cleanup_mount_file $mount_path
  cleanup $vg_name "$devs" "$infile" "$outfile" "$config_name"
}

# This test will check if a user set
# CONTAINER_ROOT_LV_NAME="container-root-lv" and
# CONTAINER_ROOT_LV_MOUNT_PATH="/var/lib/containers", then
# container-storage-setup would create a logical volume named
# "container-root-lv" and mount it on "/var/lib/containers".
test_container_root_volume
