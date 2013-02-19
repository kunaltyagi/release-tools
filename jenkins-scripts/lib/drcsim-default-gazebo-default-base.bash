#!/bin/bash -x
set -e

. ${SCRIPT_DIR}/lib/boilerplate_prepare.sh

if [ -z ${GZ_BUILD_TYPE} ]; then
    GZ_CMAKE_BUILD_TYPE=
else
    GZ_CMAKE_BUILD_TYPE="-DCMAKE_BUILD_TYPE=${GZ_BUILD_TYPE}"
fi

cat > build.sh << DELIM
###################################################
# Make project-specific changes here
#
set -ex

# get ROS repo's key
apt-get install -y wget
sh -c 'echo "deb http://packages.ros.org/ros/ubuntu precise main" > /etc/apt/sources.list.d/ros-latest.list'
wget http://packages.ros.org/ros.key -O - | apt-key add -
# Also get drc repo's key, to be used in getting Gazebo
sh -c 'echo "deb http://packages.osrfoundation.org/drc/ubuntu precise main" > /etc/apt/sources.list.d/drc-latest.list'
wget http://packages.osrfoundation.org/drc.key -O - | apt-key add -
apt-get update

# Step 1: install everything you need

# Install drcsim's and gazebo Build-Depends
apt-get install -y cmake debhelper ros-fuerte-pr2-mechanism ros-fuerte-std-msgs ros-fuerte-common-msgs ros-fuerte-image-common ros-fuerte-geometry ros-fuerte-pr2-controllers ros-fuerte-geometry-experimental ros-fuerte-image-pipeline build-essential  libfreeimage-dev libprotoc-dev libprotobuf-dev protobuf-compiler freeglut3-dev libcurl4-openssl-dev libtinyxml-dev libtar-dev libtbb-dev ros-fuerte-visualization-common libxml2-dev pkg-config libqt4-dev ros-fuerte-urdfdom ros-fuerte-console-bridge libltdl-dev libboost-thread-dev libboost-signals-dev libboost-system-dev libboost-filesystem-dev libboost-program-options-dev libboost-regex-dev libboost-iostreams-dev cppcheck ros-fuerte-robot-model-visualization osrf-common sandia-hand

# Install Bullet from source
apt-get install -y unzip
BULLET_VERSION=2.81-rev2613
wget --quiet -O $WORKSPACE/bullet-\$BULLET_VERSION.zip https://bullet.googlecode.com/files/bullet-\$BULLET_VERSION.zip
rm -rf $WORKSPACE/bullet-\$BULLET_VERSION
cd $WORKSPACE
unzip $WORKSPACE/bullet-\$BULLET_VERSION.zip
mkdir -p $WORKSPACE/bullet-build
cd $WORKSPACE/bullet-build
cmake -G "Unix Makefiles" -DBUILD_SHARED_LIBS=ON $WORKSPACE/bullet-\$BULLET_VERSION
make -j3
make install

# Normal cmake routine for Gazebo
apt-get install -y mercurial
rm -fr $WORKSPACE/gazebo
hg clone https://bitbucket.org/osrf/gazebo $WORKSPACE/gazebo

rm -rf $WORKSPACE/gazebo/build $WORKSPACE/gazebo/install
mkdir -p $WORKSPACE/gazebo/build $WORKSPACE/gazebo/install
cd $WORKSPACE/gazebo/build
CMAKE_PREFIX_PATH=/opt/ros/fuerte cmake ${GZ_CMAKE_BUILD_TYPE} -DCMAKE_INSTALL_PREFIX=/usr $WORKSPACE/gazebo
make -j3
make install
. /usr/local/share/gazebo-1.*/setup.sh

# Step 3: configure and build drcim

# Normal cmake routine
. /opt/ros/fuerte/setup.sh
. /usr/local/share/gazebo/setup.sh
rm -rf $WORKSPACE/build $WORKSPACE/install
mkdir -p $WORKSPACE/build $WORKSPACE/install
cd $WORKSPACE/build
cmake ${GZ_CMAKE_BUILD_TYPE} -DCMAKE_INSTALL_PREFIX=$WORKSPACE/install $WORKSPACE/drcsim
make -j3
make install
SHELL=/bin/sh . $WORKSPACE/install/share/drcsim/setup.sh
DISPLAY=:0 ROS_TEST_RESULTS_DIR=$WORKSPACE/build/test_results make test ARGS="-VV" || true
ROS_TEST_RESULTS_DIR=$WORKSPACE/build/test_results rosrun rosunit clean_junit_xml.py
DELIM

# Make project-specific changes here
###################################################

sudo $WORKSPACE/pbuilder  --execute \
    --bindmounts $WORKSPACE \
    --basetgz $basetgz \
    -- build.sh
