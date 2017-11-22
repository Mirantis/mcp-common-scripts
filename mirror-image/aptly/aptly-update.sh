#!/bin/bash
CLEANUP_SNAPSHOTS=0
RECREATE=0
FORCE_OVERWRITE=0
PUBLISHER_OPTIONS=""
while getopts "c?f?r?"  option
do
 case "${option}"
 in
 c|\?) CLEANUP_SNAPSHOTS=1;;
 f|\?) FORCE_OVERWRITE=1;;
 r|\?) RECREATE=1;;
 esac
done
if [ $CLEANUP_SNAPSHOTS -eq 1 ]; then
    echo "Cleanup"
    PUBLISH_LIST="$(aptly publish list --raw)"
    if [ "$PUBLISH_LIST" != "" ]; then
        echo "===> Deleting all publishes"
        echo $PUBLISH_LIST | awk '{print $2, $1}' | xargs -n2 aptly publish drop
    fi
    SNAPSHOT_LIST="$(aptly snapshot list --raw)"
    if [ "$SNAPSHOT_LIST" != "" ]; then
        echo "===> Deleting all snapshots"
        echo $SNAPSHOT_LIST | grep -E '*' | xargs -n 1 aptly snapshot drop
    fi
fi
aptly_mirror_update.sh -v -s
if [[ $? -ne 0 ]]; then
    echo "Aptly mirror update failed."
    exit 1
fi
nohup aptly api serve --no-lock > /dev/null 2>&1 </dev/null &
if [ $RECREATE -eq 1 ]; then
     echo "Recreate"
     PUBLISHER_OPTIONS+=" --recreate"
fi
if [ $FORCE_OVERWRITE -eq 1 ]; then
     PUBLISHER_OPTIONS+=" --force-overwrite"
fi
     echo "aptly-publisher --timeout=1200 publish -v -c /etc/aptly-publisher.yaml --url http://127.0.0.1:8080 $PUBLISHER_OPTIONS"
    if [[ $? -ne 0 ]]; then
        echo "Aptly Publisher failed."
        exit 1
    fi
ps aux  |  grep -i "aptly api serve"  |  awk '{print $2}'  |  xargs kill -9
aptly db cleanup
exit 0