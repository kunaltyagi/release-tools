#!/bin/bash -x

# Knowing Script dir beware of symlink
[[ -L ${0} ]] && SCRIPT_DIR=$(readlink ${0}) || SCRIPT_DIR=${0}
SCRIPT_DIR="${SCRIPT_DIR%/*}"

# Needs it own script to be able to install basel as prehook
# Overwite for Bug: https://askubuntu.com/questions/769467/can-not-install-openjdk-9-jdk-because-it-tries-to-overwrite-file-aready-includ 
DOCKER_POSTINSTALL_HOOK="""\
echo '# BEGIN SECTION: install bazel' && \\
echo \"deb [arch=amd64] http://storage.googleapis.com/bazel-apt stable jdk1.8\" | tee /etc/apt/sources.list.d/bazel.list && \\
wget -qO - https://bazel.build/bazel-release.pub.gpg | apt-key add - && \\
apt-get update && \\
apt-get install -o Dpkg::Options::=\"--force-overwrite\" -y openjdk-8-jdk bazel && \\
update-alternatives --install \"/usr/bin/java\" \"java\" \"/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java\" 1 && \\
update-alternatives --install \"/usr/bin/javac\" \"javac\" \"/usr/lib/jvm/java-8-openjdk-amd64/bin/javac\" 1 && \\
update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java && \\
update-alternatives --set javac /usr/lib/jvm/java-8-openjdk-amd64/bin/javac && \\
echo '# END SECTION'
"""

. ${SCRIPT_DIR}/lib/debian-git-repo-base.bash