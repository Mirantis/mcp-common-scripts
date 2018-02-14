#!/bin/bash
DIR="$PWD"
while getopts "d:"  option
do
 case "${option}"
  in
  d|\?) DIR="${OPTARG}";;
  esac
done

mkdir $DIR

PAYLOAD_LINE=`awk '/^__PAYLOAD_BELOW__/ {print NR + 1; exit 0; }' $0`

tail -n+$PAYLOAD_LINE $0 | tar xzv -C $DIR

REPOS="$(ls -1 $DIR)"

for REPO in $REPOS
do
    aptly repo add $REPO $DIR/$REPO
    SNAPSHOT_NAME="$REPO-$(date +%Y%m%d-%H%M%S)"
    aptly snapshot create $SNAPSHOT_NAME from repo $REPO
done

aptly_publish_update.sh -av

exit 0

__PAYLOAD_BELOW__