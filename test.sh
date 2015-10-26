#!/bin/bash

readlink_() {
  local src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    local dir="$(cd -P "$( dirname "$src" )" && pwd)"
    local src="$(readlink "$src")"
    [[ $src != /* ]] && src="$dir/$src"
  done
  echo "$(cd -P "$( dirname "$src" )" && pwd)"
}

_pwd=`readlink_ $0`

err() {
  echo "$@" >&2
}

die() {
  err "$@"
  exit 1
}

finish() {
  cd "$_pwd"
  if [ "$no_clean" -eq 0 ]; then
    find test -name *.deb -type f | xargs rm -f
  fi
}

trap "finish" EXIT

usage() {
  # Local var because of grep
  local helpdoc='HELP'
  local helpdoc+='DOC'
  echo 'Usage: test.sh [opts]'
  echo 'Opts:'
  grep "$helpdoc" "$_pwd/test.sh" -B 1 | egrep -v '^--$' | sed -e 's/^  //g' -e "s/# $helpdoc: //g"
}

vagrant_clean() {
  vagrant destroy -f upstart systemd
}

failures=0
no_clean=0
single_project_test=

while [ -n "$1" ]; do
  param="$1"
  value="$2"
  case $param in
    --clean)
      # HELPDOC: Run all clean up tasks and exit (no tests will be run)
      echo 'Removing test resources'
      finish
      vagrant_clean
      trap - EXIT
      trap
      echo 'Clean up complete'
      exit 0
      ;;
    --clean-first)
      # HELPDOC: Run all clean up tasks then run all tests
      echo 'Removing test resources'
      finish
      vagrant_clean
      echo 'Clean up complete'
      ;;
    -h | --help)
      # HELPDOC: Display this message and exit
      usage
      exit 0
      ;;
    --no-clean)
      # HELPDOC: Don't delete files generated during the tests
      no_clean=1
      ;;
    --only)
      # HELPDOC: Run only a single test by name
      if echo "$value" | egrep -q '[^a-zA-Z0-9\-_]' | egrep -q '^test-'; then
        die "Invalid test name: $value"
      fi
      single_project_test="$value"
      shift
      ;;
    *)
      echo "Invalid option: $param" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

cd "$_pwd"

### TESTS ###

test-simple-project() {
  echo "Running tests for simple-project"
  cd "$_pwd/test/simple-project"
  local is_success=1
  output=`../../node-deb --no-delete-temp -- app.js lib/`

  if [ "$?" -ne 0 ]; then
    local is_success=0
    err "$output"
  fi

  local output_dir='simple-project_0.1.0_all/'

  if ! grep -q 'Package: simple-project' "$output_dir/DEBIAN/control"; then
    err 'Package name was wrong'
    local is_success=0
  fi

  if ! grep -q 'Version: 0.1.0' "$output_dir/DEBIAN/control"; then
    err 'Package version was wrong'
    local is_success=0
  fi

  if [ "$is_success" -eq 1 ]; then
    echo "Success for simple-project"
    rm -rf "$output_dir"
  else
    err "Failure for simple project"
    : $((failures++))
  fi
}

test-whitespace-project() {
  echo "Running tests for whitespace-project"
  cd "$_pwd/test/whitespace-project"

  local is_success=1

  output=`../../node-deb -- 'whitespace file.js' 'whitespace folder' 2>&1`
  if [ "$?" -ne 0 ]; then
    local is_success=0
  fi

  output+='\n'
  output+=`../../node-deb --  whitespace\ file.js whitespace\ folder 2>&1`
  if [ "$?" -ne 0 ]; then
    local is_success=0
  fi

  if [[ $output == '*No such file or directory*' ]]; then
    err 'There was an error with the test.'
    err -e "$output"
    err 'Unable to locate a directory. This is likely an error with `find`.'
  fi

  if [ "$is_success" -eq 1 ]; then
    echo "Success for whitespace-project"
  else
    err "Failure for whitespace-project"
    : $((failures++))
  fi
}

test-node-deb-override-project() {
  echo "Running tests for node-deb-override-project"
  cd "$_pwd/test/node-deb-override-project"
  local is_success=1
  output=`../../node-deb --no-delete-temp -- app.js lib/`

  if [ "$?" -ne 0 ]; then
    local is_success=0
    err "$output"
  fi

  local output_dir='overriden-package-name_0.1.1_all/'

  if ! grep -q 'Package: overriden-package-name' "$output_dir/DEBIAN/control"; then
    err 'Package name was wrong'
    local is_success=0
  fi

  if ! grep -q 'Version: 0.1.1' "$output_dir/DEBIAN/control"; then
    err 'Package version name was wrong'
    local is_success=0
  fi

  if ! grep -q 'Maintainer: overriden maintainer' "$output_dir/DEBIAN/control"; then
    err 'Package maintainer was wrong'
    local is_success=0
  fi

  if ! grep -q 'Description: overriden description' "$output_dir/DEBIAN/control"; then
    err 'Package description was wrong'
    local is_success=0
  fi

  if [ "$is_success" -eq 1 ]; then
    echo "Success for simple-project"
    rm -rf "$output_dir"
  else
    err "Failure for simple project"
    : $((failures++))
  fi
}

test-commandline-override-project() {
  echo "Running tests for commandline-override-project"
  cd "$_pwd/test/commandline-override-project"
  local is_success=1
  output=`../../node-deb --no-delete-temp \
    -n overriden-package-name \
    -v 0.1.1 \
    -u overriden-user \
    -g overriden-group \
    -m 'overriden maintainer' \
    -d 'overriden description' \
    -- app.js lib/`

  if [ "$?" -ne 0 ]; then
    local is_success=0
    err "$output"
  fi

  local output_dir='overriden-package-name_0.1.1_all/'

  if ! grep -q 'Package: overriden-package-name' "$output_dir/DEBIAN/control"; then
    err 'Package name was wrong'
    local is_success=0
  fi

  if ! grep -q 'Version: 0.1.1' "$output_dir/DEBIAN/control"; then
    err 'Package version name was wrong'
    local is_success=0
  fi

  if ! grep -q 'Maintainer: overriden maintainer' "$output_dir/DEBIAN/control"; then
    err 'Package maintainer was wrong'
    local is_success=0
  fi

  if ! grep -q 'Description: overriden description' "$output_dir/DEBIAN/control"; then
    err 'Package description was wrong'
    local is_success=0
  fi

  if [ "$is_success" -eq 1 ]; then
    echo "Success for simple-project"
    rm -rf "$output_dir"
  else
    err "Failure for simple project"
    : $((failures++))
  fi
}

test-upstart-project() {
  echo 'Running tests for upstart-project'
  local target_file='/var/log/upstart-project/TEST_OUTPUT'

  vagrant up --provision upstart && \
  vagrant ssh upstart -c "if [ -a '$target_file' ]; then sudo rm -rfv '$target_file'; fi" && \
  echo 'Sleeping...' && \
  sleep 3 && \
  vagrant ssh upstart -c "[ -f '$target_file' ]"

  if [ "$?" -ne 0 ]; then
    err 'Failure on checking file existence for target host'
    : $((failures++))
  else
    vagrant destroy -f upstart
    echo 'Success for upstart-project'
  fi
}

test-systemd-project() {
  echo 'Running tests for systemd-project'
  local target_file='/var/log/systemd-project/TEST_OUTPUT'

  vagrant up --provision systemd && \
  vagrant ssh systemd -c "if [ -a '$target_file' ]; then sudo rm -rfv '$target_file'; fi" && \
  echo 'Sleeping...' && \
  sleep 3 && \
  vagrant ssh systemd -c "[ -f '$target_file' ]"

  if [ "$?" -ne 0 ]; then
    err 'Failure on checking file existence for target host'
    : $((failures++))
  else
    vagrant destroy -f systemd
    echo 'Success for systemd-project'
  fi
}

if [ -n "$single_project_test" ]; then
  echo '--------------------------'
  eval "$single_project_test"
  echo '--------------------------'
else
  echo '--------------------------'
  test-simple-project
  echo '--------------------------'
  test-whitespace-project
  echo '--------------------------'
  test-node-deb-override-project
  echo '--------------------------'
  test-commandline-override-project
  echo '--------------------------'
  test-upstart-project
  echo '--------------------------'
  test-systemd-project
  echo '--------------------------'
fi

trap - EXIT
trap

if [ "$failures" -eq 0 ]; then
  echo "Success for all tests"
  finish
  exit 0
else
  die "Tests contained $failures failure(s)."
fi