source $SRCDIR/libtest.sh

main(){
local docker_graph_option="--graph"
local docker_graph_dir="/tmp/docker"
local delimiter=" "

# Test with $docker_graph_option = '--graph' and $docker_graph_dir = '/tmp/docker'
# and $delimiter ' ' i.e --graph /tmp/docker
if ! test_docker_root_volume_non_default $docker_graph_option $delimiter $docker_graph_dir; then
   return 1
fi

# Test with $docker_graph_option = '--graph' and $docker_graph_dir = '/tmp/docker'
# and $delimiter '=' i.e --graph=/tmp/docker
delimiter="="
if ! test_docker_root_volume_non_default $docker_graph_option $delimiter $docker_graph_dir; then
   return 1
fi

# Test with $docker_graph_option = '-g' and $docker_graph_dir = '/tmp/docker'
# and delimiter '=' i.e. -g=/tmp/docker
docker_graph_option="-g"
if ! test_docker_root_volume_non_default $docker_graph_option $delimiter $docker_graph_dir; then
   return 1
fi

# Test with $docker_graph_option = '-g' and $docker_graph_dir = '/tmp/docker'
# and delimiter ' ' i.e. -g /tmp/docker
delimiter=" "
if ! test_docker_root_volume_non_default $docker_graph_option $delimiter $docker_graph_dir; then
   return 1
fi
}

# Test DOCKER_ROOT_VOLUME= directive. Returns 0 on success and 1 on failure.
test_docker_root_volume_non_default() {
  local devs=$TEST_DEVS
  local test_status=1
  local testname=`basename "$0"`
  local vg_name="dss-test-foo"
  local docker_root_lv_name="docker-root-lv"

  # Error out if any pre-existing volume group vg named dss-test-foo
  if vg_exists "$vg_name"; then
    echo "ERROR: $testname: Volume group $vg_name already exists." >> $LOGS
    return $test_status
  fi

  # Create config file
  cat << EOF > /etc/sysconfig/docker-storage-setup
DEVS="$devs"
VG=$vg_name
DOCKER_ROOT_VOLUME=yes
DOCKER_ROOT_VOLUME_SIZE=40%FREE
EOF

 # Create /etc/sysconfig/docker file.
  if ! create_docker_config $1 $2 $3; then
     echo "ERROR: $testname: Creating /etc/sysconfig/docker config file." >> $LOGS
     cleanup $vg_name "$devs"
     return $test_status
  fi

 # Run docker-storage-setup
 $DSSBIN >> $LOGS 2>&1

 # Test failed.
 if [ $? -ne 0 ]; then
    echo "ERROR: $testname: $DSSBIN Failed." >> $LOGS
    cleanup $vg_name "$devs"
    mv /etc/sysconfig/docker.backup /etc/sysconfig/docker >/dev/null 2>&1
    rmdir "$3" >/dev/null 2>&1
    return $test_status
 fi

  # Make sure $DOCKER_ROOT_VOLUME {docker-root-lv} got created
  # successfully.
  if lv_exists "$docker_root_lv_name"; then
    test_status=0
  fi

   # Make sure $DOCKER_ROOT_VOLUME {docker-root-lv} is
   # mounted on $docker_graph_dir
   local mnt
   mnt=$(findmnt -n -o TARGET --first-only --source /dev/${vg_name}/${docker_root_lv_name})
   if [ "$mnt" == "$3" ];then
      test_status=0
   fi

  $DSSBIN --reset >> $LOGS 2>&1
  # Test failed.
  if [ $? -eq 0 ]; then
     if [ ! -e /etc/sysconfig/docker-storage ]; then
          test_status=0
     fi
  fi
  if [ ${test_status} -eq 1 ]; then
     echo "ERROR: $testname: $DSSBIN --reset Failed." >> $LOGS
  fi

  cleanup $vg_name "$devs"
  mv /etc/sysconfig/docker.backup /etc/sysconfig/docker >/dev/null 2>&1
  rmdir "$3" >/dev/null 2>&1
  return $test_status
}

create_docker_config(){
# Take a backup if /etc/sysconfig/docker already exists.
if [ -f /etc/sysconfig/docker ];then
   mv /etc/sysconfig/docker /etc/sysconfig/docker.backup
fi
  cat << EOF > /etc/sysconfig/docker
OPTIONS='--selinux-enabled --log-driver=journald $1$2$3'
DOCKER_CERT_PATH=/etc/docker
EOF
}

main "$@"
