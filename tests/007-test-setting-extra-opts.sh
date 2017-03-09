source $SRCDIR/libtest.sh

# Test that the user-specified options stored in
# EXTRA_DOCKER_STORAGE_OPTIONS actually end up in
# the docker storage config file, appended to the variable
# DOCKER_STORAGE_OPTIONS in /etc/sysconfig/docker-storage
test_set_extra_docker_opts() {
  local devs=$TEST_DEVS
  local test_status=1
  local testname=`basename "$0"`
  local vg_name="css-test-foo"
  local extra_options="--storage-opt dm.fs=ext4"
  local infile="/etc/sysconfig/docker-storage-setup"
  local outfile="/etc/sysconfig/docker-storage"
  local default_config_name="docker"

  # Error out if volume group $vg_name exists already
  if vg_exists "$vg_name"; then
    echo "ERROR: $testname: Volume group $vg_name already exists" >> $LOGS
    return $test_status
  fi

  cat << EOF > $infile
DEVS="$devs"
VG=$vg_name
EXTRA_DOCKER_STORAGE_OPTIONS="$extra_options"
EOF

  # Run container-storage-setup
  $CSSBIN >> $LOGS 2>&1

  # css failed
  if [ $? -ne 0 ]; then
    echo "ERROR: $testname: $CSSBIN --reset failed." >> $LOGS
    cleanup $vg_name "$devs" "$infile" "$outfile" "$default_config_name"
    return $test_status
  fi

  # Check if docker-storage config file was created by css
  if [ ! -f $outfile ]; then
    echo "ERROR: $testname: $outfile file was not created." >> $LOGS
    cleanup $vg_name "$devs" "$infile" "$outfile" "$default_config_name"
    return $test_status
  fi

  source $outfile

  # Search for $extra_options in $options.
  echo $DOCKER_STORAGE_OPTIONS | grep -q -- "$extra_options"

  # Successful appending to DOCKER_STORAGE_OPTIONS
  if [ $? -eq 0 ]; then
    test_status=0
  else
    echo "ERROR: $testname: failed. DOCKER_STORAGE_OPTIONS ${DOCKER_STORAGE_OPTIONS} does not include extra_options ${extra_options}." >> $LOGS
  fi

  cleanup $vg_name "$devs" "$infile" "$outfile" "$default_config_name"
  return $test_status
}

# Test that $EXTRA_DOCKER_STORAGE_OPTIONS is successfully written
# into /etc/sysconfig/docker-storage
test_set_extra_docker_opts
