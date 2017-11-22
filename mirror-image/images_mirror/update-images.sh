#!/bin/bash
FILES="$(cat /srv/images.txt)"
for FILE in $FILES
do
  FILENAME=`echo $FILE | sed 's/.*\///g'`
  if [ -f "/srv/http/images/$FILENAME" ]; then
      MD5=`md5sum /srv/http/images/$FILENAME | awk '{ print $1 }'`
      echo "===> File /srv/http/images/$FILENAME exists and it's MD5 hash is: $MD5"
  else
      MD5="None"
      echo "===> File /srv/http/images/$FILENAME doesn't exist"
  fi
  wget http://apt.mirantis.com/images/$FILENAME.md5 -q -O /srv/http/images/$FILENAME.md5
  MD5UPSTREAM=`cat /srv/http/images/$FILENAME.md5 | awk '{ print $1 }'`
  rm /srv/http/images/$FILENAME.md5
  if [ "$MD5" != "$MD5UPSTREAM" ];
    then
      echo "Hashes of image $FILENAME don't match."
      echo "Local MD5 hash is:    $MD5"
      echo "Upstream MD5 hash is: $MD5UPSTREAM"
      rm /srv/http/images/$FILENAME
      wget http://apt.mirantis.com/images/$FILENAME -O /srv/http/images/$FILENAME
    else
      echo "Hashes of image $FILENAME match."
  fi
done