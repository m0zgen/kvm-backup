#!/bin/bash
# Manual clean backups older than MAXBACKUPS 
# Created by Yevgeniy Goncharov, https://sys-adm.in

SERVER=""
SHARE="/mnt/win-share/"
MAXBACKUPS=1

CLEAN_SERVERS=(server1 server2 server3)

for s in "${CLEAN_SERVERS[@]}"; do
	echo "$SHARE$s"

	LIST=$(ls -r1 $SHARE$s  | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$')
	i=1

	for b in $LIST; do
		if [ $i -gt "$MAXBACKUPS" ]; then
	        echo "Removing old backup "`basename $b`
	        cd $SHARE$s
	        rm -rf "$b"
	    fi

	    i=$[$i+1]
	done
done




