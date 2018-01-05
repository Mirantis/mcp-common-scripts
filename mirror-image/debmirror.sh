#!/bin/bash

DEBMLOG=/var/log/debmirror.log
MIRRORDIR=/srv/aptly/public

if test -s $DEBMLOG
then
test -f $DEBMLOG.3.gz && mv $DEBMLOG.3.gz $DEBMLOG.4.gz
test -f $DEBMLOG.2.gz && mv $DEBMLOG.2.gz $DEBMLOG.3.gz
test -f $DEBMLOG.1.gz && mv $DEBMLOG.1.gz $DEBMLOG.2.gz
test -f $DEBMLOG.0 && mv $DEBMLOG.0 $DEBMLOG.1 && gzip $DEBMLOG.1
mv $DEBMLOG $DEBMLOG.0
cp /dev/null $DEBMLOG
chmod 640 $DEBMLOG
fi

# Record the current date/time
date 2>&1 | tee -a $DEBMLOG

# Ubuntu General
echo "\n*** Ubuntu Mirror ***\n" 2>&1 | tee -a $DEBMLOG
debmirror --i18n --method=http --progress \
--host=mirror.mirantis.com \
$MIRRORDIR/ubuntu \
--arch=amd64 \
--dist=xenial,xenial-security,xenial-updates,xenial-backports \
--root=$MCP_VERSION/ubuntu \
--dist=main,multiverse,restricted,universe \
--rsync-extra=none \
--ignore-small-errors \
--exclude-deb-section=games \
--exclude-deb-section=gnome \
--exclude-deb-section=graphics \
--exclude-deb-section=kde \
--exclude-deb-section=video \
2>&1 | tee -a $DEBMLOG

echo "\n*** Fixing ownership ***\n" 2>&1 | tee -a $DEBMLOG
find $MIRRORDIR -type d -o -type f -exec chown aptly:aptly '{}' \; \
2>&1 | tee -a $DEBMLOG

echo "\n*** Fixing permissions ***\n" 2>&1 | tee -a $DEBMLOG
find $MIRRORDIR -type d -o -type f -exec chmod u+rw,g+r,o+r-w {} \; \
2>&1 | tee -a $DEBMLOG

echo "\n*** Mirror size ***\n" 2>&1 | tee -a $DEBMLOG
du -hs $MIRRORDIR 2>&1 | tee -a $DEBMLOG

# Record the current date/time
date 2>&1 | tee -a $DEBMLOG