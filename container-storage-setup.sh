#!/bin/bash

#--
# Copyright 2014-2017 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#++

#  Purpose:  This script sets up the storage for container runtimes.
#  Author:   Andy Grimm <agrimm@redhat.com>

set -e

# container-storage-setup version information
_CSS_MAJOR_VERSION="0"
_CSS_MINOR_VERSION="2"
_CSS_SUBLEVEL="0"
_CSS_EXTRA_VERSION=""

_CSS_VERSION="${_CSS_MAJOR_VERSION}.${_CSS_MINOR_VERSION}.${_CSS_SUBLEVEL}"
[ -n "$_CSS_EXTRA_VERSION" ] && _CSS_VERSION="${_CSS_VERSION}-${_CSS_EXTRA_VERSION}"

# This section reads the config file $INPUTFILE
# Read man page for a description of currently supported options:
# 'man container-storage-setup'

_DOCKER_ROOT_LV_NAME="docker-root-lv"
_DOCKER_ROOT_DIR="/var/lib/docker"
_DOCKER_METADATA_DIR="/var/lib/docker"
DOCKER_ROOT_VOLUME_SIZE=40%FREE

_DOCKER_COMPAT_MODE=""
_STORAGE_IN_FILE=""
_STORAGE_OUT_FILE=""
_STORAGE_DRIVERS="devicemapper overlay overlay2"

_PIPE1=/run/css-$$-fifo1
_PIPE2=/run/css-$$-fifo2
_TEMPDIR=$(mktemp --tmpdir -d)

# DEVS can have device names without absolute path. Convert these to absolute
# paths and save in ABS_DEVS and use in rest of the code.
_DEVS_ABS=""

# Will have currently configured storage options in ${_STORAGE_OUT_FILE}
_CURRENT_STORAGE_OPTIONS=""

_STORAGE_OPTIONS="STORAGE_OPTIONS"

get_docker_version() {
  local version

  # docker version command exits with error as daemon is not running at this
  # point of time. So continue despite the error.
  version=`docker version --format='{{.Client.Version}}' 2>/dev/null` || true
  echo $version
}

get_deferred_removal_string() {
  local version major minor

  if ! version=$(get_docker_version);then
    return 0
  fi
  [ -z "$version" ] && return 0

  major=$(echo $version | cut -d "." -f1)
  minor=$(echo $version | cut -d "." -f2)
  [ -z "$major" ] && return 0
  [ -z "$minor" ] && return 0

  # docker 1.7 onwards supports deferred device removal. Enable it.
  if [ $major -gt 1 ] ||  ([ $major -eq 1 ] && [ $minor -ge 7 ]);then
    echo "--storage-opt dm.use_deferred_removal=true"
  fi
}

get_deferred_deletion_string() {
  local version major minor

  if ! version=$(get_docker_version);then
    return 0
  fi
  [ -z "$version" ] && return 0

  major=$(echo $version | cut -d "." -f1)
  minor=$(echo $version | cut -d "." -f2)
  [ -z "$major" ] && return 0
  [ -z "$minor" ] && return 0

  if should_enable_deferred_deletion $major $minor; then
     echo "--storage-opt dm.use_deferred_deletion=true"
  fi
}

should_enable_deferred_deletion() {
   # docker 1.9 onwards supports deferred device deletion. Enable it.
   local major=$1
   local minor=$2
   if [ $major -lt 1 ] || ([ $major -eq 1 ] && [ $minor -lt 9 ]);then
      return 1
   fi
   if platform_supports_deferred_deletion; then
      return 0
   fi
   return 1
}

platform_supports_deferred_deletion() {
        local deferred_deletion_supported=1
        trap cleanup_pipes EXIT
        local child_exec="$_SRCDIR/css-child-read-write.sh"

        [ ! -x "$child_exec" ] && child_exec="/usr/share/container-storage-setup/css-child-read-write"

        if [ ! -x "$child_exec" ];then
           return 1
        fi
        mkfifo $_PIPE1
        mkfifo $_PIPE2
        unshare -m ${child_exec} $_PIPE1 $_PIPE2 "$_TEMPDIR" &
        read -t 10 n <>$_PIPE1
        if [ "$n" != "start" ];then
	   return 1
        fi
        rmdir $_TEMPDIR > /dev/null 2>&1
        deferred_deletion_supported=$?
        echo "finish" > $_PIPE2
        return $deferred_deletion_supported
}

cleanup_pipes(){
    rm -f $_PIPE1
    rm -f $_PIPE2
    rmdir $_TEMPDIR 2>/dev/null
}

extra_options_has_dm_fs() {
  local option
  for option in ${EXTRA_STORAGE_OPTIONS}; do
    if grep -q "dm.fs=" <<< $option; then
      return 0
    fi
  done
  return 1
}

# Wait for a device for certain time interval. If device is found 0 is
# returned otherwise 1.
wait_for_dev() {
  local devpath=$1
  local timeout=$DEVICE_WAIT_TIMEOUT

  if [ -b "$devpath" ];then
    Info "Device node $devpath exists."
    return 0
  fi

  if [ -z "$DEVICE_WAIT_TIMEOUT" ] || [ "$DEVICE_WAIT_TIMEOUT" == "0" ];then
    Info "Not waiting for device $devpath as DEVICE_WAIT_TIMEOUT=${DEVICE_WAIT_TIMEOUT}."
    return 0
  fi

  while [ $timeout -gt 0 ]; do
    Info "Waiting for device $devpath to be available. Wait time remaining is $timeout seconds"
    if [ $timeout -le 5 ];then
      sleep $timeout
    else
      sleep 5
    fi
    timeout=$((timeout-5))
    if [ -b "$devpath" ]; then
      Info "Device node $devpath exists."
      return 0
    fi
  done

  Info "Timed out waiting for device $devpath"
  return 1
}

get_devicemapper_config_options() {
  local storage_options
  local dm_fs="--storage-opt dm.fs=xfs"

  # docker expects device mapper device and not lvm device. Do the conversion.
  eval $( lvs --nameprefixes --noheadings -o lv_name,kernel_major,kernel_minor $VG | while read line; do
    eval $line
    if [ "$LVM2_LV_NAME" = "$CONTAINER_THINPOOL" ]; then
      echo _POOL_DEVICE_PATH=/dev/mapper/$( cat /sys/dev/block/${LVM2_LV_KERNEL_MAJOR}:${LVM2_LV_KERNEL_MINOR}/dm/name )
    fi
  done )

  if extra_options_has_dm_fs; then
    # dm.fs option defined in ${EXTRA_STORAGE_OPTIONS}
    dm_fs=""
  fi

  storage_options="${_STORAGE_OPTIONS}=\"--storage-driver devicemapper ${dm_fs} --storage-opt dm.thinpooldev=$_POOL_DEVICE_PATH $(get_deferred_removal_string) $(get_deferred_deletion_string) ${EXTRA_STORAGE_OPTIONS}\""
  echo $storage_options
}

get_config_options() {
  if [ "$1" == "devicemapper" ]; then
    get_devicemapper_config_options
    return $?
  fi
  echo "${_STORAGE_OPTIONS}=\"--storage-driver $1 ${EXTRA_STORAGE_OPTIONS}\""
  return 0
}

write_storage_config_file () {
  local storage_driver=$1
  local storage_out_file=$2
  local storage_options

  if ! storage_options=$(get_config_options $storage_driver); then
      return 1
  fi

  cat <<EOF > ${storage_out_file}.tmp
$storage_options
EOF

  mv -Z ${storage_out_file}.tmp ${storage_out_file}
}

convert_size_in_bytes() {
  local size=$1 prefix suffix

  # if it is all numeric, it is valid as by default it will be MiB.
  if [[ $size =~ ^[[:digit:]]+$ ]]; then
    echo $(($size*1024*1024))
    return 0
  fi

  # supprt G, G[bB] or Gi[bB] inputs.
  prefix=${size%[bBsSkKmMgGtTpPeE]i[bB]}
  prefix=${prefix%[bBsSkKmMgGtTpPeE][bB]}
  prefix=${prefix%[bBsSkKmMgGtTpPeE]}

  # if prefix is not all numeric now, it is an error.
  if ! [[ $prefix =~ ^[[:digit:]]+$ ]]; then
    return 1
  fi

  suffix=${data_size#$prefix}

  case $suffix in
    b*|B*) echo $prefix;;
    s*|S*) echo $(($prefix*512));;
    k*|K*) echo $(($prefix*2**10));;
    m*|M*) echo $(($prefix*2**20));;
    g*|G*) echo $(($prefix*2**30));;
    t*|T*) echo $(($prefix*2**40));;
    p*|P*) echo $(($prefix*2**50));;
    e*|E*) echo $(($prefix*2**60));;
    *) return 1;;
  esac
}

data_size_in_bytes() {
  local data_size=$1
  local bytes vg_size free_space percent

  # -L compatible syntax
  if [[ $DATA_SIZE != *%* ]]; then
    bytes=`convert_size_in_bytes $data_size`
    [ $? -ne 0 ] && return 1
    # If integer overflow took place, value is too large to handle.
    if [ $bytes -lt 0 ];then
      Error "DATA_SIZE=$data_size is too large to handle."
      return 1
    fi
    echo $bytes
    return 0
  fi

  if [[ $DATA_SIZE == *%FREE ]];then
    free_space=$(vgs --noheadings --nosuffix --units b -o vg_free $VG)
    percent=${DATA_SIZE%\%FREE}
    echo $((percent*free_space/100))
    return 0
  fi

  if [[ $DATA_SIZE == *%VG ]];then
    vg_size=$(vgs --noheadings --nosuffix --units b -o vg_size $VG)
    percent=${DATA_SIZE%\%VG}
    echo $((percent*vg_size/100))
  fi
  return 0
}

check_min_data_size_condition() {
  local min_data_size_bytes data_size_bytes free_space

  [ -z $MIN_DATA_SIZE ] && return 0

  if ! check_numeric_size_syntax $MIN_DATA_SIZE; then
    Fatal "MIN_DATA_SIZE value $MIN_DATA_SIZE is invalid."
  fi

  if ! min_data_size_bytes=$(convert_size_in_bytes $MIN_DATA_SIZE);then
    Fatal "Failed to convert MIN_DATA_SIZE to bytes"
  fi

  # If integer overflow took place, value is too large to handle.
  if [ $min_data_size_bytes -lt 0 ];then
    Fatal "MIN_DATA_SIZE=$MIN_DATA_SIZE is too large to handle."
  fi

  free_space=$(vgs --noheadings --nosuffix --units b -o vg_free $VG)

  if [ $free_space -lt $min_data_size_bytes ];then
    Fatal "There is not enough free space in volume group $VG to create data volume of size MIN_DATA_SIZE=${MIN_DATA_SIZE}."
  fi

  if ! data_size_bytes=$(data_size_in_bytes $DATA_SIZE);then
    Fatal "Failed to convert desired data size to bytes"
  fi

  if [ $data_size_bytes -lt $min_data_size_bytes ]; then
    # Increasing DATA_SIZE to meet minimum data size requirements.
    Info "DATA_SIZE=${DATA_SIZE} is smaller than MIN_DATA_SIZE=${MIN_DATA_SIZE}. Will create data volume of size specified by MIN_DATA_SIZE."
    DATA_SIZE=$MIN_DATA_SIZE
  fi
}

create_lvm_thin_pool () {
  if [ -z "$_DEVS_ABS" ] && [ -z "$_VG_EXISTS" ]; then
    Fatal "Specified volume group $VG does not exist, and no devices were specified"
  fi

  if [ ! -n "$DATA_SIZE" ]; then
    Fatal "DATA_SIZE not specified."
  fi

  if ! check_data_size_syntax $DATA_SIZE; then
    Fatal "DATA_SIZE value $DATA_SIZE is invalid."
  fi

  check_min_data_size_condition

  # Calculate size of metadata lv. Reserve 0.1% of the free space in the VG
  # for docker metadata.
  _VG_SIZE=$(vgs --noheadings --nosuffix --units s -o vg_size $VG)
  _META_SIZE=$(( $_VG_SIZE / 1000 + 1 ))

  if [ -z "$_META_SIZE" ];then
    Fatal "Failed to calculate metadata volume size."
  fi

  if [ -n "$CHUNK_SIZE" ]; then
    _CHUNK_SIZE_ARG="-c $CHUNK_SIZE"
  fi

  if [[ $DATA_SIZE == *%* ]]; then
    _DATA_SIZE_ARG="-l $DATA_SIZE"
  else
    _DATA_SIZE_ARG="-L $DATA_SIZE"
  fi

  lvcreate -y --type thin-pool --zero n $_CHUNK_SIZE_ARG --poolmetadatasize ${_META_SIZE}s $_DATA_SIZE_ARG -n $CONTAINER_THINPOOL $VG
}

get_configured_thin_pool() {
  local options tpool opt

  options=$_CURRENT_STORAGE_OPTIONS
  [ -z "$options" ] && return 0

  # This assumes that thin pool is specified as dm.thinpooldev=foo. There
  # are no spaces in between.
  for opt in $options; do
    if [[ $opt =~ dm.thinpooldev* ]];then
      tpool=${opt#*=}
      echo "$tpool"
      return 0
    fi
  done
}

check_docker_storage_metadata() {
  local docker_devmapper_meta_dir="$_DOCKER_METADATA_DIR/devicemapper/metadata/"

  [ ! -d "$docker_devmapper_meta_dir" ] && return 0

  # Docker seems to be already using devicemapper storage driver. Error out.
  Error "Docker has been previously configured for use with devicemapper graph driver. Not creating a new thin pool as existing docker metadata will fail to work with it. Manual cleanup is required before this will succeed."
  Info "Docker state can be reset by stopping docker and by removing ${_DOCKER_METADATA_DIR} directory. This will destroy existing docker images and containers and all the docker metadata."
  exit 1
}

systemd_escaped_filename () {
  local escaped_path filename path=$1
  escaped_path=$(echo ${path}|sed 's|-|\\x2d|g')
  filename=$(echo ${escaped_path}.mount|sed 's|/|-|g' | cut -b 2-)
  echo $filename
}


#
# In the past we created a systemd mount target file, we no longer
# use it, but if one pre-existed we still need to handle it.
#
remove_systemd_mount_target () {
  local mp=$1
  local filename=$(systemd_escaped_filename $mp)
  if [ -f /etc/systemd/system/$filename ]; then
      if [ -x /usr/bin/systemctl ];then      
	  systemctl disable $filename >/dev/null 2>&1
	  systemctl stop $filename >/dev/null 2>&1
	  systemctl daemon-reload
      fi
    rm -f /etc/systemd/system/$filename >/dev/null 2>&1
  fi
}

reset_extra_volume () {
  local mp filename
  local lv_name=$1
  local mount_dir=$2
  local vg=$3

  if extra_volume_exists $lv_name $vg; then
    mp=$(extra_lv_mountpoint $lv_name $mount_dir)
    if [ -n "$mp" ];then
      if ! umount $mp >/dev/null 2>&1; then
        Fatal "Failed to unmount $mp"
      fi
    fi
    lvchange -an $vg/${lv_name}
    lvremove $vg/${lv_name}
  else
    return 0
  fi
  # If the user has manually unmounted mount directory, mountpoint (mp)
  # will be empty. Extract ${mp} from $(mount_dir) in that case.
  if [ -z "$mp" ];then
    mp=${mount_dir}
  fi
  remove_systemd_mount_target $mp
}

reset_lvm_thin_pool () {
  local thinpool_name=$1
  local vg=$2
  if lvm_pool_exists $thinpool_name $vg; then
      lvchange -an $vg/${thinpool_name}
      lvremove $vg/${thinpool_name}
  fi
}

setup_lvm_thin_pool () {
  local tpool
  # Check if a thin pool is already configured in /etc/sysconfig/docker-storage.
  # If yes, wait for that thin pool to come up.
  tpool=`get_configured_thin_pool`
  local thinpool_name=${CONTAINER_THINPOOL}

  if [ -n "$tpool" ]; then
     local escaped_pool_lv_name=`echo $thinpool_name | sed 's/-/--/g'`
     Info "Found an already configured thin pool $tpool in ${_STORAGE_OUT_FILE}"

     # css generated thin pool device name starts with /dev/mapper/ and
     # ends with $thinpool_name
     if [[ "$tpool" != /dev/mapper/*${escaped_pool_lv_name} ]];then
       Fatal "Thin pool ${tpool} does not seem to be managed by container-storage-setup. Exiting."
     fi

     if ! wait_for_dev "$tpool"; then
       Fatal "Already configured thin pool $tpool is not available. If thin pool exists and is taking longer to activate, set DEVICE_WAIT_TIMEOUT to a higher value and retry. If thin pool does not exist any more, remove ${_STORAGE_OUT_FILE} and retry"
     fi
  fi

  # At this point of time, a volume group should exist for lvm thin pool
  # operations to succeed. Make that check and fail if that's not the case.
  if ! vg_exists "$VG";then
    Fatal "No valid volume group found. Exiting."
  else
    _VG_EXISTS=1
  fi

  if ! lvm_pool_exists $thinpool_name $VG; then
    [ -n "$_DOCKER_COMPAT_MODE" ] && check_docker_storage_metadata
    create_lvm_thin_pool
    [ -n "$_STORAGE_OUT_FILE" ] &&  write_storage_config_file $STORAGE_DRIVER "$_STORAGE_OUT_FILE"
  else
    # At this point /etc/sysconfig/docker-storage file should exist. If user
    # deleted this file accidently without deleting thin pool, recreate it.
    if [ -n "$_STORAGE_OUT_FILE" -a ! -f "${_STORAGE_OUT_FILE}" ];then
      Info "${_STORAGE_OUT_FILE} file is missing. Recreating it."
      write_storage_config_file $STORAGE_DRIVER "$_STORAGE_OUT_FILE"
    fi
  fi

  # Enable or disable automatic pool extension
  if [ "$AUTO_EXTEND_POOL" == "yes" ];then
    enable_auto_pool_extension ${VG} ${thinpool_name}
  else
    disable_auto_pool_extension ${VG} ${thinpool_name}
  fi
}

lvm_pool_exists() {
  local lv_data
  local lvname lv lvsize
  local thinpool_name=$1
  local vg=$2

  if [ -z "$thinpool_name" ]; then
      Fatal "Thin pool name must be specified."
  fi
  lv_data=$( lvs --noheadings -o lv_name,lv_attr --separator , $vg | sed -e 's/^ *//')
  SAVEDIFS=$IFS
  for lv in $lv_data; do
  IFS=,
  read lvname lvattr <<< "$lv"
    # pool logical volume has "t" as first character in its attributes
    if [ "$lvname" == "$thinpool_name" ] && [[ $lvattr == t* ]]; then
      IFS=$SAVEDIFS
      return 0
    fi
  done
  IFS=$SAVEDIFS

  return 1
}

# If a ${_STORAGE_OUT_FILE} file is present and if it contains
# dm.datadev or dm.metadatadev entries, that means we have used old mode
# in the past.
is_old_data_meta_mode() {
  if [ ! -f "${_STORAGE_OUT_FILE}" ];then
    return 1
  fi

  if ! grep -e "^${_STORAGE_OPTIONS}=.*dm\.datadev" -e "^${_STORAGE_OPTIONS}=.*dm\.metadatadev" ${_STORAGE_OUT_FILE}  > /dev/null 2>&1;then
    return 1
  fi

  return 0
}

grow_root_pvs() {
  # If root is not in a volume group, then there are no root pvs and nothing
  # to do.
  [ -z "$_ROOT_PVS" ] && return 0

  # Grow root pvs only if user asked for it through config file.
  [ "$GROWPART" != "true" ] && return

  if [ ! -x "/usr/bin/growpart" ];then
    Error "GROWPART=true is specified and /usr/bin/growpart executable is not available. Install /usr/bin/growpart and try again."
    return 1
  fi

  # Note that growpart is only variable here because we may someday support
  # using separate partitions on the same disk.  Today we fail early in that
  # case.  Also note that the way we are doing this, it should support LVM
  # RAID for the root device.  In the mirrored or striped case, we are growing
  # partitions on all disks, so as long as they match, growing the LV should
  # also work.
  for pv in $_ROOT_PVS; do
    # Split device & partition.  Ick.
    growpart $( echo $pv | sed -r 's/([^0-9]*)([0-9]+)/\1 \2/' ) || true
    pvresize $pv
  done
}

grow_root_lv_fs() {
  if [ -n "$ROOT_SIZE" ]; then
    # TODO: Error checking if specified size is <= current size
    lvextend -r -L $ROOT_SIZE $_ROOT_DEV || true
  fi
}

# Determines if a device is already added in a volume group as pv. Returns
# 0 on success.
is_dev_part_of_vg() {
  local dev=$1
  local vg=$2

  if ! pv_name=$(pvs --noheadings -o pv_name -S pv_name=$dev,vg_name=$vg); then
    Fatal "Error running command pvs. Exiting."
  fi

 [ -z "$pv_name" ] && return 1
 pv_name=`echo $pv_name | tr -d '[ ]'`
 [ "$pv_name" == "$dev" ] && return 0
 return 1
}

# Check if passed in vg exists. Returns 0 if volume group exists.
vg_exists() {
  local check_vg=$1

  for vg_name in $(vgs --noheadings -o vg_name); do
    if [ "$vg_name" == "$VG" ]; then
      return 0
    fi
  done
  return 1
}

is_block_dev_partition() {
  local bdev=$1 devparent

  if ! disktype=$(lsblk -n --nodeps --output type ${bdev}); then
    Fatal "Failed to run lsblk on device $bdev"
  fi

  if [ "$disktype" == "part" ];then
    return 0
  fi

  # For loop device partitions, lsblk reports type as "loop" and not "part".
  # So check if device has a parent in the tree and if it does, there are high
  # chances it is partition (except the case of lvm volumes)
  if ! devparent=$(lsblk -npls -o NAME ${bdev}|tail -n +2); then
    Fatal "Failed to run lsblk on device $bdev"
  fi

  if [ -n "$devparent" ];then
    return 0
  fi

  return 1
}

check_wipe_block_dev_sig() {
  local bdev=$1
  local sig

  if ! sig=$(wipefs -p $bdev); then
    Fatal "Failed to check signatures on device $bdev"
  fi

  [ "$sig" == "" ] && return 0

  if [ "$WIPE_SIGNATURES" == "true" ];then
    Info "Wipe Signatures is set to true. Any signatures on $bdev will be wiped."
    if ! wipefs -a $bdev; then
      Fatal "Failed to wipe signatures on device $bdev"
    fi
    return 0
  fi

  while IFS=, read offset uuid label type; do
    [ "$offset" == "# offset" ] && continue
    Fatal "Found $type signature on device ${bdev} at offset ${offset}. Wipe signatures using wipefs or use WIPE_SIGNATURES=true and retry."
  done <<< "$sig"
}

# Make sure passed in devices are valid block devies. Also make sure they
# are not partitions. Names which are of the form "sdb", convert them to
# their absolute path for processing in rest of the script.
canonicalize_block_devs() {
  local devs=$1 dev
  local devs_abs dev_abs
  local dest_dev

  for dev in ${devs}; do
    # If the device name is a symlink, follow it and use the target
    if [ -h "$dev" ];then
      if ! dest_dev=$(readlink -e $dev);then
        Fatal "Failed to resolve symbolic link $dev"
      fi
      dev=$dest_dev
    fi
    # Looks like we allowed just device name (sda) as valid input. In
    # such cases /dev/$dev should be a valid block device.
    dev_abs=$dev
    [ ! -b "$dev" ] && dev_abs="/dev/$dev"
    [ ! -b "$dev_abs" ] && Fatal "$dev_abs is not a valid block device."

    if is_block_dev_partition ${dev_abs}; then
      Fatal "Partition specification unsupported at this time."
    fi
    devs_abs="$devs_abs $dev_abs"
  done

  # Return list of devices to caller.
  echo "$devs_abs"
}

# Scans all the disks listed in DEVS= and returns the disks which are not
# already part of volume group and are new and require further processing.
scan_disks() {
  local disk_list="$1"
  local vg=$2
  local wipe_signatures=$3
  local new_disks=""

  for dev in $disk_list; do
    local part=$(dev_query_first_child $dev)

    if [ -n "$part" ] && is_dev_part_of_vg ${part} $vg; then
      Info "Device ${dev} is already partitioned and is part of volume group $VG"
      continue
    fi

    # If signatures are being overridden, then simply return the disk as new
    # disk. Even if it is partitioned, partition signatures will be wiped.
    if [ "$wipe_signatures" == "true" ];then
      new_disks="$new_disks $dev"
      continue
    fi

    # If device does not have partitions, it is a new disk requiring processing.
    if [[ -z "$part" ]]; then
      new_disks="$dev $new_disks"
      continue
    fi

    Fatal "Device $dev is already partitioned and cannot be added to volume group $vg"
  done

  echo $new_disks
}

create_partition_sfdisk(){
  local dev="$1" size
  # Use a single partition of a whole device
  # TODO:
  #   * Consider gpt, or unpartitioned volumes
  #   * Error handling when partition(s) already exist
  #   * Deal with loop/nbd device names. See growpart code
  size=$(( $( awk "\$4 ~ /"$( basename $dev )"/ { print \$3 }" /proc/partitions ) * 2 - 2048 ))
    cat <<EOF | sfdisk $dev
unit: sectors

start=     2048, size=  ${size}, Id=8e
EOF
}

create_partition_parted(){
  local dev="$1"
  parted $dev --script mklabel msdos mkpart primary 0% 100% set 1 lvm on
}

create_partition() {
  local dev="$1" part

  if [ -x "/usr/sbin/parted" ]; then
    create_partition_parted $dev
  else
    create_partition_sfdisk $dev
  fi

  # Sometimes on slow storage it takes a while for partition device to
  # become available. Wait for device node to show up.
  if ! udevadm settle;then
    Fatal "udevadm settle after partition creation failed. Exiting."
  fi

  part=$(dev_query_first_child $dev)

  if ! wait_for_dev ${part}; then
    Fatal "Partition device ${part} is not available"
  fi
}

dev_query_first_child() {
  lsblk -npl -o NAME "$1" | tail -n +2 | head -1
}

create_disk_partitions() {
  local devs="$1" part

  for dev in $devs; do
    create_partition $dev
    part=$(dev_query_first_child $dev)

    # By now we have ownership of disk and we have checked there are no
    # signatures on disk or signatures should be wiped. Don't care
    # about any signatures found in the middle of disk after creating
    # partition and wipe signatures if any are found.
    if ! wipefs -f -a ${part}; then
      Fatal "Failed to wipe signatures on device ${part}"
    fi
    pvcreate ${part}
    _PVS="$_PVS ${part}"
  done
}

create_extend_volume_group() {
  if [ -z "$_VG_EXISTS" ]; then
    vgcreate $VG $_PVS
    _VG_EXISTS=1
  else
    # TODO:
    #   * Error handling when PV is already part of a VG
    vgextend $VG $_PVS
  fi
}

# Auto extension logic. Create a profile for pool and attach that profile
# the pool volume.
enable_auto_pool_extension() {
  local volume_group=$1
  local pool_volume=$2
  local profileName="${volume_group}--${pool_volume}-extend"
  local profileFile="${profileName}.profile"
  local profileDir
  local tmpFile=`mktemp -p /run -t tmp.XXXXX`

  profileDir=$(lvm dumpconfig | grep "profile_dir" | cut -d "=" -f2 | sed 's/"//g')
  [ -n "$profileDir" ] || return 1

  if [ ! -n "$POOL_AUTOEXTEND_THRESHOLD" ];then
    Error "POOL_AUTOEXTEND_THRESHOLD not specified"
    return 1
  fi

  if [ ! -n "$POOL_AUTOEXTEND_PERCENT" ];then
    Error "POOL_AUTOEXTEND_PERCENT not specified"
    return 1
  fi

  cat <<EOF > $tmpFile
activation {
	thin_pool_autoextend_threshold=${POOL_AUTOEXTEND_THRESHOLD}
	thin_pool_autoextend_percent=${POOL_AUTOEXTEND_PERCENT}

}
EOF
  mv -Z $tmpFile ${profileDir}/${profileFile}
  lvchange --metadataprofile ${profileName}  ${volume_group}/${pool_volume}
}

disable_auto_pool_extension() {
  local volume_group=$1
  local pool_volume=$2
  local profileName="${volume_group}--${pool_volume}-extend"
  local profileFile="${profileName}.profile"
  local profileDir

  profileDir=$(lvm dumpconfig | grep "profile_dir" | cut -d "=" -f2 | sed 's/"//g')
  [ -n "$profileDir" ] || return 1

  lvchange --detachprofile ${volume_group}/${pool_volume}
  rm -f ${profileDir}/${profileFile}
}


# Gets the current ${_STORAGE_OPTIONS}= string.
get_current_storage_options() {
  local options

  if [ ! -f "${_STORAGE_OUT_FILE}" ];then
    return 0
  fi

  if options=$(grep -e "^${_STORAGE_OPTIONS}=" ${_STORAGE_OUT_FILE} | sed "s/${_STORAGE_OPTIONS}=//" | sed 's/^ *//' | sed 's/^"//' | sed 's/"$//');then
    echo $options
    return 0
  fi

  return 1
}

is_valid_storage_driver() {
  local driver=$1 d

  for d in $_STORAGE_DRIVERS;do
    [ "$driver" == "$d" ] && return 0
  done

  return 1
}

# Gets the existing storage driver configured in /etc/sysconfig/docker-storage
get_existing_storage_driver() {
  local options driver

  options=$_CURRENT_STORAGE_OPTIONS

  [ -z "$options" ] && return 0

  # Check if -storage-driver <driver> is there.
  if ! driver=$(echo $options | sed -n 's/.*\(--storage-driver [ ]*[a-z0-9]*\).*/\1/p' | sed 's/--storage-driver *//');then
    return 1
  fi

  # If pattern does not match then driver == options.
  if [ -n "$driver" ] && [ ! "$driver" == "$options" ];then
    echo $driver
    return 0
  fi

  # Check if -s <driver> is there.
  if ! driver=$(echo $options | sed -n 's/.*\(-s [ ]*[a-z][0-9]*\).*/\1/p' | sed 's/-s *//');then
    return 1
  fi

  # If pattern does not match then driver == options.
  if [ -n "$driver" ] && [ ! "$driver" == "$options" ];then
    echo $driver
    return 0
  fi

  # We shipped some versions where we did not specify -s devicemapper.
  # If dm.thinpooldev= is present driver is devicemapper.
  if echo $options | grep -q -e "--storage-opt dm.thinpooldev=";then
    echo "devicemapper"
    return 0
  fi

  #Failed to determine existing storage driver.
  return 1
}

extra_volume_exists() {
  local lv_name=$1
  local vg=$2

  lvs $vg/$lv_name > /dev/null 2>&1 && return 0
  return 1
}

# This returns the mountpoint of $1
extra_lv_mountpoint() {
  local mounts
  local lv_name=$1
  local mount_dir=$2
  mounts=$(findmnt -n -o TARGET --source /dev/$VG/$lv_name | grep $mount_dir)
  echo $mounts
}

mount_extra_volume() {
  local lv_name=$1
  local mount_dir=$2
  remove_systemd_mount_target $mount_dir
  mounts=$(extra_lv_mountpoint $lv_name $mount_dir)
  if [ -z "$mounts" ]; then
      mount /dev/$VG/$lv_name $mount_dir
  fi
}

# Create a logical volume of size specified by first argument. Name of the
# volume is specified using second argument.
create_lv() {
  local data_size=$1
  local data_lv_name=$2

  # TODO: Error handling when data_size > available space.
  if [[ $data_size == *%* ]]; then
    lvcreate -y -l $data_size -n $data_lv_name $VG || return 1
  else
    lvcreate -y -L $data_size -n $data_lv_name $VG || return 1
  fi
return 0
}

setup_extra_volume() {
  local lv_name=$1
  local mount_dir=$2
  local lv_size=$3

  if ! create_lv $lv_size $lv_name; then
    Fatal "Failed to create volume $lv_name of size ${lv_size}."
  fi

  if ! mkfs -t xfs /dev/$VG/$lv_name > /dev/null; then
    Fatal "Failed to create filesystem on /dev/$VG/${lv_name}."
  fi

  if ! mount_extra_volume $lv_name $mount_dir; then
    Fatal "Failed to mount volume ${lv_name} on ${mount_dir}"
  fi

  # setup right selinux label first time fs is created. Mount operation
  # changes the label of directory to reflect the label on root inode
  # of mounted fs.
  if ! restore_selinux_context $mount_dir; then
    return 1
  fi
}

setup_extra_lv_fs() {
  [ -z "$_RESOLVED_MOUNT_DIR_PATH" ] && return 0
  if ! setup_extra_dir $_RESOLVED_MOUNT_DIR_PATH; then
    return 1
  fi
  if extra_volume_exists $CONTAINER_ROOT_LV_NAME $VG; then
    if ! mount_extra_volume $CONTAINER_ROOT_LV_NAME $_RESOLVED_MOUNT_DIR_PATH; then
      Fatal "Failed to mount volume $CONTAINER_ROOT_LV_NAME on $_RESOLVED_MOUNT_DIR_PATH"
    fi
    return 0
  fi
  if [ -z "$CONTAINER_ROOT_LV_SIZE" ]; then
    Fatal "Specify a valid value for CONTAINER_ROOT_LV_SIZE."
  fi
  if ! check_data_size_syntax $CONTAINER_ROOT_LV_SIZE; then
    Fatal "CONTAINER_ROOT_LV_SIZE value $CONTAINER_ROOT_LV_SIZE is invalid."
  fi
  # Container runtime extra volume does not exist. Create one.
  if ! setup_extra_volume $CONTAINER_ROOT_LV_NAME $_RESOLVED_MOUNT_DIR_PATH $CONTAINER_ROOT_LV_SIZE; then
    Fatal "Failed to setup extra volume $CONTAINER_ROOT_LV_NAME."
  fi
}

setup_docker_root_lv_fs() {
  [ "$DOCKER_ROOT_VOLUME" != "yes" ] && return 0
  if ! setup_docker_root_dir; then
    return 1
  fi
  if extra_volume_exists $_DOCKER_ROOT_LV_NAME $VG; then
    if ! mount_extra_volume $_DOCKER_ROOT_LV_NAME $_DOCKER_ROOT_DIR; then
      Fatal "Failed to mount volume $_DOCKER_ROOT_LV_NAME on $_DOCKER_ROOT_DIR"
    fi
    return 0
  fi
  if [ -z "$DOCKER_ROOT_VOLUME_SIZE" ]; then
    Fatal "Specify a valid value for DOCKER_ROOT_VOLUME_SIZE."
  fi
  if ! check_data_size_syntax $DOCKER_ROOT_VOLUME_SIZE; then
    Fatal "DOCKER_ROOT_VOLUME_SIZE value $DOCKER_ROOT_VOLUME_SIZE is invalid."
  fi
  # Docker root volume does not exist. Create one.
  if ! setup_extra_volume $_DOCKER_ROOT_LV_NAME $_DOCKER_ROOT_DIR $DOCKER_ROOT_VOLUME_SIZE; then
    Fatal "Failed to setup logical volume $_DOCKER_ROOT_LV_NAME."
  fi
}

check_storage_options(){
  if [ "$STORAGE_DRIVER" == "devicemapper" ] && [ -z "$CONTAINER_THINPOOL" ];then
     Fatal "CONTAINER_THINPOOL must be defined for the devicemapper storage driver."
  fi

  # Populate $_RESOLVED_MOUNT_DIR_PATH
  if [ -n "$CONTAINER_ROOT_LV_MOUNT_PATH" ];then
    if ! _RESOLVED_MOUNT_DIR_PATH=$(realpath $CONTAINER_ROOT_LV_MOUNT_PATH);then
	Fatal "Failed to resolve path $CONTAINER_ROOT_LV_MOUNT_PATH"
    fi
  fi

  if [ "$DOCKER_ROOT_VOLUME" == "yes" ] && [ -n "$CONTAINER_ROOT_LV_MOUNT_PATH" ];then
     Fatal "DOCKER_ROOT_VOLUME and CONTAINER_ROOT_LV_MOUNT_PATH are mutually exclusive options."
  fi

  if [ -n "$CONTAINER_ROOT_LV_NAME" ] && [ -z "$CONTAINER_ROOT_LV_MOUNT_PATH" ];then
     Fatal "CONTAINER_ROOT_LV_MOUNT_PATH cannot be empty, when CONTAINER_ROOT_LV_NAME is set"
  fi

  if [ -n "$CONTAINER_ROOT_LV_MOUNT_PATH" ] && [ -z "$CONTAINER_ROOT_LV_NAME" ];then
     Fatal "CONTAINER_ROOT_LV_NAME cannot be empty, when CONTAINER_ROOT_LV_MOUNT_PATH is set"
  fi

  # Allow using DOCKER_ROOT_VOLUME only in compatibility mode.
  if [ "$DOCKER_ROOT_VOLUME" == "yes" ] && [ "$_DOCKER_COMPAT_MODE" != "1" ];then
     Fatal "DOCKER_ROOT_VOLUME is deprecated. Use CONTAINER_ROOT_LV_MOUNT_PATH instead."
  fi

  if [ "$DOCKER_ROOT_VOLUME" == "yes" ];then
     Info "DOCKER_ROOT_VOLUME is deprecated, and will be removed soon. Use CONTAINER_ROOT_LV_MOUNT_PATH instead."
  fi

  if [ -n "${EXTRA_DOCKER_STORAGE_OPTIONS}" ]; then
      Info "EXTRA_DOCKER_STORAGE_OPTIONS is deprecated, please use EXTRA_STORAGE_OPTIONS"
      if [ -n "${EXTRA_STORAGE_OPTIONS}" ]; then
	  Fatal "EXTRA_DOCKER_STORAGE_OPTIONS and EXTRA_STORAGE_OPTIONS are mutually exclusive options."
      fi
      EXTRA_STORAGE_OPTIONS=${EXTRA_DOCKER_STORAGE_OPTIONS}
      unset EXTRA_DOCKER_STORAGE_OPTIONS
  fi
}

setup_storage() {
  local current_driver

  if [ "$STORAGE_DRIVER" == "" ];then
    Info "STORAGE_DRIVER not set, no storage will be configured. You must specify STORAGE_DRIVER if you want to configure storage."
    exit 0
  fi

  if ! is_valid_storage_driver $STORAGE_DRIVER;then
    Fatal "Invalid storage driver: ${STORAGE_DRIVER}."
  fi

  # Query and save current storage options
  if ! _CURRENT_STORAGE_OPTIONS=$(get_current_storage_options); then
    return 1
  fi

  if ! current_driver=$(get_existing_storage_driver);then
    Fatal "Failed to determine existing storage driver."
  fi

  # If storage is configured and new driver should match old one.
  if [ -n "$current_driver" ] && [ "$current_driver" != "$STORAGE_DRIVER" ];then
   Fatal "Storage is already configured with ${current_driver} driver. Can't configure it with ${STORAGE_DRIVER} driver. To override, remove ${_STORAGE_OUT_FILE} and retry."
  fi

  # If a user decides to setup (a) and (b)/(c):
  # a) lvm thin pool for devicemapper.
  # b) a separate volume for container runtime root.
  # c) a separate named ($CONTAINER_ROOT_LV_NAME) volume for $CONTAINER_ROOT_LV_MOUNT_PATH.
  # (a) will be setup first, followed by (b) or (c).

  # Set up lvm thin pool LV.
  if [ "$STORAGE_DRIVER" == "devicemapper" ]; then
    setup_lvm_thin_pool
  else
      write_storage_config_file $STORAGE_DRIVER "$_STORAGE_OUT_FILE"
  fi

  # If container root is on a separate volume, setup that.
  if ! setup_docker_root_lv_fs; then
    Error "Failed to setup docker root volume."
    return 1
  fi

  # Set up a separate named ($CONTAINER_ROOT_LV_NAME) volume
  # for $CONTAINER_ROOT_LV_MOUNT_PATH.
  if ! setup_extra_lv_fs; then
    Error "Failed to setup logical volume for $CONTAINER_ROOT_LV_MOUNT_PATH."
    return 1
  fi
}

restore_selinux_context() {
  local dir=$1

  if ! restorecon -R $dir; then
    Error "restorecon -R $dir failed."
    return 1
  fi
}

get_docker_root_dir(){
    local flag=false path
    options=$(grep -e "^OPTIONS" /etc/sysconfig/docker|cut -d"'" -f 2)
    for opt in $options
    do
        if [ "$flag" = true ];then
           path=$opt
           flag=false
           continue
        fi
	case "$opt" in
            "-g"|"--graph")
                flag=true
                ;;
            -g=*|--graph=*)
		path=$(echo $opt|cut -d"=" -f 2)
                ;;
            *)
                ;;
        esac
    done
    if [ -z "$path" ];then
      return
    fi
    if ! _DOCKER_ROOT_DIR=$(realpath -m $path);then
      Fatal "Failed to resolve path $path"
    fi
}

setup_extra_dir() {
  local resolved_mount_dir_path=$1
  [ -d "$resolved_mount_dir_path" ] && return 0

  # Directory does not exist. Create one.
  mkdir -p $resolved_mount_dir_path
  return $?
}

setup_docker_root_dir() {
  if ! get_docker_root_dir; then
    return 1
  fi

  [ -d "_$DOCKER_ROOT_DIR" ] && return 0

  # Directory does not exist. Create one.
  mkdir -p $_DOCKER_ROOT_DIR
  return $?
}


# This deals with determining rootfs, root vg and pvs etc and sets the
# global variables accordingly.
determine_rootfs_pvs_vg() {
  # Read mounts
  _ROOT_DEV=$( awk '$2 ~ /^\/$/ && $1 !~ /rootfs/ { print $1 }' /proc/mounts )
  if ! _ROOT_VG=$(lvs --noheadings -o vg_name $_ROOT_DEV 2>/dev/null);then
    Info "Volume group backing root filesystem could not be determined"
    _ROOT_VG=
  else
    _ROOT_VG=$(echo $_ROOT_VG | sed -e 's/^ *//' -e 's/ *$//')
  fi

  _ROOT_PVS=
  if [ -n "$_ROOT_VG" ];then
    _ROOT_PVS=$( pvs --noheadings -o pv_name,vg_name | awk "\$2 ~ /^$_ROOT_VG\$/ { print \$1 }" )
  fi

  _VG_EXISTS=
  if [ -z "$VG" ]; then
    if [ -n "$_ROOT_VG" ]; then
      VG=$_ROOT_VG
      _VG_EXISTS=1
    fi
  else
    if vg_exists "$VG";then
      _VG_EXISTS=1
    fi
  fi
}

partition_disks_create_vg() {
  local dev_list

  # If there is no volume group specified or no root volume group, there is
  # nothing to do in terms of dealing with disks.
  if [[ -n "$DEVS" && -n "$VG" ]]; then
    _DEVS_ABS=$(canonicalize_block_devs "${DEVS}")

    # If all the disks have already been correctly partitioned, there is
    # nothing more to do
    dev_list=$(scan_disks "$_DEVS_ABS" "$VG" "$WIPE_SIGNATURES")
    if [[ -n "$dev_list" ]]; then
      for dev in $dev_list; do
        check_wipe_block_dev_sig $dev
      done
      create_disk_partitions "$dev_list"
      create_extend_volume_group
    fi
  fi
}

reset_storage() {
  if [ -n "$_RESOLVED_MOUNT_DIR_PATH" ] && [ -n "$CONTAINER_ROOT_LV_NAME" ];then
    reset_extra_volume $CONTAINER_ROOT_LV_NAME $_RESOLVED_MOUNT_DIR_PATH $VG
  fi

  if [ "$DOCKER_ROOT_VOLUME" == "yes" ];then
    if ! get_docker_root_dir; then
      return 1
    fi
    reset_extra_volume $_DOCKER_ROOT_LV_NAME $_DOCKER_ROOT_DIR $VG
  fi

  if [ "$STORAGE_DRIVER" == "devicemapper" ]; then
    reset_lvm_thin_pool ${CONTAINER_THINPOOL} $VG
  fi
  rm -f ${_STORAGE_OUT_FILE}
}

usage() {
  cat <<-FOE
    Usage: $1 [OPTIONS] INPUTFILE OUTPUTFILE

    Grows the root filesystem and sets up storage for container runtimes

    Options:
      --help    Print help message
      --reset   Reset your docker storage to init state. 
      --version Print version information.
FOE
}

# Source library. If there is a library present in same dir as d-s-s, source
# that otherwise fall back to standard library. This is useful when modifyin
# libcss.sh in git tree and testing d-s-s.
_SRCDIR=`dirname $0`

if [ -e $_SRCDIR/libcss.sh ]; then
  source $_SRCDIR/libcss.sh
elif [ -e /usr/share/container-storage-setup/libcss.sh ]; then
  source /usr/share/container-storage-setup/libcss.sh
fi

if [ -e $_SRCDIR/container-storage-setup.conf ]; then
  source $_SRCDIR/container-storage-setup.conf
elif [ -e /usr/share/container-storage-setup/container-storage-setup ]; then
  source /usr/share/container-storage-setup/container-storage-setup
fi

# Main Script
_OPTS=`getopt -o hv -l reset -l help -l version -- "$@"`
eval set -- "$_OPTS"
_RESET=0
while true ; do
    case "$1" in
        --reset) _RESET=1; shift;;
        -h | --help)  usage $(basename $0); exit 0;;
        -v | --version)  echo $_CSS_VERSION; exit 0;;
        --) shift; break;;
    esac
done

case $# in
    0)
	CONTAINER_THINPOOL=docker-pool
	_DOCKER_COMPAT_MODE=1
	_STORAGE_IN_FILE="/etc/sysconfig/docker-storage-setup"
	_STORAGE_OUT_FILE="/etc/sysconfig/docker-storage"
	;;
    2)
	_STORAGE_IN_FILE=$1
	_STORAGE_OUT_FILE=$2
	;;
    *)
	usage $(basename $0) >&2
	exit 1
	;;
esac

if [ -n "$_DOCKER_COMPAT_MODE" ]; then
   _STORAGE_OPTIONS="DOCKER_STORAGE_OPTIONS"
fi

# If user has overridden any settings in $_STORAGE_IN_FILE
# take that into account.
if [ -e "${_STORAGE_IN_FILE}" ]; then
  source ${_STORAGE_IN_FILE}
fi

# Verify storage options set correctly in input files
check_storage_options

determine_rootfs_pvs_vg

if [ $_RESET -eq 1 ]; then
    reset_storage
    exit 0
fi

partition_disks_create_vg
grow_root_pvs

# NB: We are growing root here first, because when root and docker share a
# disk, we'll default to giving some portion of remaining space to docker.
# Do this operation only if root is on a logical volume.
[ -n "$_ROOT_VG" ] && grow_root_lv_fs

if is_old_data_meta_mode; then
  Fatal "Old mode of passing data and metadata logical volumes to docker is not supported. Exiting."
fi

setup_storage
