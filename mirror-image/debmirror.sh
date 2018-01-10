#!/bin/bash

set -xe
set -o pipefail
stamp=$(date "+%Y_%m_%d_%H_%M_%S")
DEBMLOG=/var/log/debmirror/${stamp}.log
MIRRORDIR=/srv/aptly/public
MCP_VERSION=${MCP_VERSION:-stable}
MIRROR_HOST=${MIRROR_HOST:-"mirror.mirantis.com"}
method=${CLONE_METHOD:-"rsync"}

if [[ ${method} == "rsync" ]] ; then
  m_root=":mirror/$MCP_VERSION/ubuntu"
elif [[ ${method} == "http" ]] ; then
  m_root="$MCP_VERSION/ubuntu"
else
  echo "LOG: Error: unsupported clone method!" 2>&1 | tee -a $DEBMLOG
  exit 1
fi

### Script body ###
echo "LOG: Start: $(date '+%Y_%m_%d_%H_%M_%S')"  2>&1 | tee -a $DEBMLOG

mkdir -p $(dirname ${DEBMLOG}) ${MIRRORDIR}
# Ubuntu General
echo "LOG: Ubuntu Mirror" 2>&1 | tee -a $DEBMLOG

debmirror --verbose --method=${method} --progress \
  --host=${MIRROR_HOST} \
  --arch=amd64 \
  --dist=xenial,xenial-security,xenial-updates \
  --root=${m_root} \
  --section=main,multiverse,restricted,universe \
  --rsync-extra=none \
  --nosource \
  --no-check-gpg \
  --exclude-deb-section=games \
  --exclude-deb-section=gnome \
  --exclude-deb-section=Xfce \
  --exclude-deb-section=sound \
  --exclude-deb-section=doc \
  --exclude-deb-section=electronics \
  --exclude-deb-section=graphics \
  --exclude-deb-section=hamradio \
  --exclude-deb-section=localization \
  --exclude-deb-section=kde \
  --exclude-deb-section=video \
  --exclude='/firefox*' \
  --exclude='/chromium-browser*' \
  --exclude='/ceph*' \
  --exclude='/*-wallpapers*' \
  --exclude='/language-pack-(?!en)' \
  $MIRRORDIR/ubuntu 2>&1 | tee -a $DEBMLOG

echo "LOG: Fixing ownership" 2>&1 | tee -a $DEBMLOG
find "${MIRRORDIR}" -type d -o -type f -exec chown aptly:aptly '{}' \; 2>&1 | tee -a $DEBMLOG

echo "LOG: Fixing permissions " 2>&1 | tee -a $DEBMLOG
find "${MIRRORDIR}" -type d -o -type f -exec chmod u+rw,g+r,o+r-w {} \; 2>&1 | tee -a $DEBMLOG

echo "LOG: Mirror size " 2>&1 | tee -a $DEBMLOG
du -hs "${MIRRORDIR}" 2>&1 | tee -a $DEBMLOG

echo "LOG: Finish:$(date '+%Y_%m_%d_%H_%M_%S')"  2>&1 | tee -a $DEBMLOG

