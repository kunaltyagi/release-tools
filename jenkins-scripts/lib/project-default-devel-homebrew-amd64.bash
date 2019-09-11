#!/bin/bash -x
set -e

# Knowing Script dir beware of symlink
if [[ -z "${SCRIPT_DIR}" ]]; then
  [[ -L ${0} ]] && SCRIPT_DIR=$(readlink ${0}) || SCRIPT_DIR=${0}
  SCRIPT_DIR="${SCRIPT_DIR%/lib/*}"
fi

export HOMEBREW_MAKE_JOBS=${MAKE_JOBS}

# Get project name as first argument to this script
PROJECT=$1 # project will have the major version included (ex gazebo2)
PROJECT_ARGS=${2}

# In ignition projects, the name of the repo and the formula does not match
PROJECT_PATH=${PROJECT}
if [[ ${PROJECT/ignition} != ${PROJECT} ]]; then
    PROJECT_PATH="ign${PROJECT/ignition}"
    PROJECT_PATH="${PROJECT_PATH/[0-9]*}"
fi

# Check for major version number
# the PROJECT_FORMULA variable is only used for dependency resolution
PROJECT_FORMULA=${PROJECT//[0-9]}$(\
  python ${SCRIPT_DIR}/tools/detect_cmake_major_version.py \
  ${WORKSPACE}/${PROJECT_PATH}/CMakeLists.txt || true)

export HOMEBREW_PREFIX=/usr/local
export HOMEBREW_CELLAR=${HOMEBREW_PREFIX}/Cellar
export PATH=${HOMEBREW_PREFIX}/bin:$PATH

# make verbose mode?
MAKE_VERBOSE_STR=""
if [[ ${MAKE_VERBOSE} ]]; then
  MAKE_VERBOSE_STR="VERBOSE=1"
fi

# Step 1. Set up homebrew
echo "# BEGIN SECTION: clean up ${HOMEBREW_PREFIX}"
. ${SCRIPT_DIR}/lib/_homebrew_cleanup.bash
. ${SCRIPT_DIR}/lib/_homebrew_base_setup.bash
brew cleanup || echo "brew cleanup couldn't be run"
mkdir -p ${HOMEBREW_CELLAR}
sudo chmod -R ug+rwx ${HOMEBREW_CELLAR}
echo '# END SECTION'

echo '# BEGIN SECTION: brew information'
# Run brew update to get latest versions of formulae
brew update
# Don't let brew auto-update any more for this session
# to ensure consistency
export HOMEBREW_NO_AUTO_UPDATE=1
# Run brew config to print system information
brew config
# Run brew doctor to check for problems with the system
brew doctor
echo '# END SECTION'

echo '# BEGIN SECTION: setup the osrf/simulation tap'
brew tap osrf/simulation
echo '# END SECTION'

if [[ -n "${PULL_REQUEST_URL}" ]]; then
  echo "# BEGIN SECTION: pulling ${PULL_REQUEST_URL}"
  brew pull ${PULL_REQUEST_URL}
  echo '# END SECTION'
fi

echo "# BEGIN SECTION: install ${PROJECT_FORMULA} dependencies"
# Process the package dependencies
brew install ${PROJECT_FORMULA} ${PROJECT_ARGS} --only-dependencies

if [[ "${RERUN_FAILED_TESTS}" -gt 0 ]]; then
  # Install lxml for flaky_junit_merge.py
  PIP_PACKAGES_NEEDED="${PIP_PACKAGES_NEEDED} lxml"
fi

if [[ -n "${PIP_PACKAGES_NEEDED}" ]]; then
  brew install python@2
  pip install ${PIP_PACKAGES_NEEDED}
fi

if [[ -z "${DISABLE_CCACHE}" ]]; then
  brew install ccache
  export PATH=/usr/local/opt/ccache/libexec:$PATH
fi
echo '# END SECTION'

# Step 3. Manually compile and install ${PROJECT}
echo "# BEGIN SECTION: configure ${PROJECT}"
cd ${WORKSPACE}/${PROJECT_PATH}
# Need the sudo since the test are running with roots perms to access to GUI
sudo rm -fr ${WORKSPACE}/build
mkdir -p ${WORKSPACE}/build
cd ${WORKSPACE}/build
 
# add X11 path so glxinfo can be found
export PATH="${PATH}:/opt/X11/bin"

# set display before cmake
# search for Xquartz instance owned by current user
export DISPLAY=$(ps ax \
  | grep '[[:digit:]]*:[[:digit:]][[:digit:]].[[:digit:]][[:digit:]] /opt/X11/bin/Xquartz' \
  | grep "auth /Users/$(whoami)/" \
  | sed -e 's@.*Xquartz @@' -e 's@ .*@@'
)

# set CMAKE_PREFIX_PATH if we are using qt5 (aka qt)
if brew ruby -e "exit ! '${PROJECT_FORMULA}'.f.recursive_dependencies.map(&:name).keep_if { |d| d == 'qt' }.empty?"; then
  export CMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH}:/usr/local/opt/qt
fi
# Workaround for tinyxml2 6.2.0: set CMAKE_PREFIX_PATH and PKG_CONFIG_PATH if we are using tinyxml2@6.2.0
if brew ruby -e "exit ! '${PROJECT_FORMULA}'.f.recursive_dependencies.map(&:name).keep_if { |d| d == 'tinyxml2@6.2.0' }.empty?"; then
  export CMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH}:/usr/local/opt/tinyxml2@6.2.0
  export PKG_CONFIG_PATH=${PKG_CONFIG_PATH}:/usr/local/opt/tinyxml2@6.2.0/lib/pkgconfig
fi
# if we are using gts, need to add gettext library path since it is keg-only
if brew ruby -e "exit ! '${PROJECT_FORMULA}'.f.recursive_dependencies.map(&:name).keep_if { |d| d == 'gettext' }.empty?"; then
  export LIBRARY_PATH=${LIBRARY_PATH}:/usr/local/opt/gettext/lib
fi

# if we are using dart@6.10.0 (custom OR port), need to add dartsim library path since it is keg-only
if brew ruby -e "exit ! '${PROJECT_FORMULA}'.f.recursive_dependencies.map(&:name).keep_if { |d| d == 'dartsim@6.10.0' }.empty?"; then
  export CMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH}:/usr/local/opt/dartsim@6.10.0
  export DYLD_FALLBACK_LIBRARY_PATH=${DYLD_FALLBACK_LIBRARY_PATH}:/usr/local/opt/dartsim@6.10.0/lib:/usr/local/opt/octomap/local
  export PKG_CONFIG_PATH=${PKG_CONFIG_PATH}:/usr/local/opt/dartsim@6.10.0/lib/pkgconfig
fi

cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_INSTALL_PREFIX=/usr/local/Cellar/${PROJECT_FORMULA}/HEAD \
     ${WORKSPACE}/${PROJECT_PATH}
echo '# END SECTION'

echo "# BEGIN SECTION: compile and install ${PROJECT_FORMULA}"
make -j${MAKE_JOBS} ${MAKE_VERBOSE_STR} install
brew link ${PROJECT_FORMULA}
echo '# END SECTION'

echo "#BEGIN SECTION: brew doctor analysis"
brew missing || brew install $(brew missing | awk '{print $2}') && brew missing
brew doctor
echo '# END SECTION'

# CHECK PRE_TESTS_EXECUTION_HOOK AND RUN
# expr length is not portable. wc -c, returns 1 on empty str
if [ `echo "${PRE_TESTS_EXECUTION_HOOK}" | wc -c` -gt 1 ]; then
  # to be able to handle hooks in a pure multiline form, this dirty hack
  TMPFILE_HOOK=$(mktemp /tmp/.brew_pretesthook_XXXX)
  cat > ${TMPFILE_HOOK} <<-DELIM
  ${PRE_TESTS_EXECUTION_HOOK}
DELIM
  . ${TMPFILE_HOOK}
  rm ${TMPFILE_HOOK}
fi

echo "# BEGIN SECTION: run tests"
# Need to clean up models before run tests (issue 27)
rm -fr \$HOME/.gazebo/models test_results*

# Run `make test`
# If it has any failures, then rerun the failed tests one time
# and merge the junit results
. ${WORKSPACE}/scripts/jenkins-scripts/lib/make_test_rerun_failed.bash
echo '# END SECTION'

echo "# BEGIN SECTION: re-add group write permissions"
sudo chmod -R ug+rwx ${HOMEBREW_CELLAR}
echo '# END SECTION'
