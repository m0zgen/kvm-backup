#!/bin/bash
# KVM guests live backup script
# Created by Yevgeniy Goncharov, https://sys-adm.in

# Envs
# ---------------------------------------------------\
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)

# Vars
# ---------------------------------------------------\
WINSHARE="//xxx.xxx.xx.x/kvm-backup$"
LOCALMNTFOLDER="win-share"
MOUNTSHARE="/mnt/$LOCALMNTFOLDER"

#
BACKUPDEST=$MOUNTSHARE
MAXBACKUPS="$3"

if [ -z "$MAXBACKUPS" ]; then
    MAXBACKUPS=6
fi

# Mount
if mount|grep $LOCALMNTFOLDER > /dev/null 2>&1; then
        echo -e "\nAlready mounted...\n"
else
    echo -e "\nNot mounted... Mounting....\n"
        /usr/bin/mount -t cifs -o username=cifsUserName,password=cifsUserPassword $WINSHARE $MOUNTSHARE
        sleep 2
fi

# Running VM list (generate automatically)
# ---------------------------------------------------\
# vm_list=`virsh list | grep running | awk '{print $2}'`

# Manually VM list
# ---------------------------------------------------\
vm_list=(server1 server2 server3)

# Log file
# ---------------------------------------------------\
logfile="/var/log/kvmbackup.log"
echo "`date +"%Y-%m-%d_%H-%M-%S"` Start backup" >> $logfile

# Enumerate VMs
# ---------------------------------------------------\

# Use if list set manually
for DOMAIN in "${vm_list[@]}"; 

# Use if list generated automatically
# for DOMAIN in $vm_list
    do
        echo "Beginning backup for $DOMAIN"
        echo "`date +"%Y-%m-%d_%H-%M-%S"` Start backup $DOMAIN" >> $logfile

        # Generate the backup path
        # ---------------------------------------------------\
        BACKUPDATE=`date "+%Y-%m-%d.%H%M%S"`
        BACKUPDOMAIN="$BACKUPDEST/$DOMAIN"
        BACKUP="$BACKUPDOMAIN/$BACKUPDATE"
        mkdir -p "$BACKUP"

        # Get disk names and image paths
        # ---------------------------------------------------\
        TARGETS=`virsh domblklist "$DOMAIN" --details | grep 'vd'| awk '{print $3}' | grep -v "^-"`
        IMAGES=`virsh domblklist "$DOMAIN" --details | grep 'vd\|hd\|sd'| awk '{print $4}' | grep -v "^-"`

        # Create the snapshot.
        # ---------------------------------------------------\
        DISKSPEC=""
        for t in $TARGETS; do
            echo $DISKSPEC
            DISKSPEC="$DISKSPEC --diskspec $t,snapshot=external"
            # echo $DISKSPEC
        done
        echo "virsh snapshot-create-as --domain "$DOMAIN" --name backup --no-metadata --atomic --disk-only $DISKSPEC"
        virsh snapshot-create-as --domain "$DOMAIN" --name backup --no-metadata --atomic --disk-only $DISKSPEC >/dev/null

        if [ $? -ne 0 ]; then
            echo "Failed to create snapshot for $DOMAIN"
            exit 1
        fi

        # Copy disk images
        # ---------------------------------------------------\
        for t in $IMAGES; do
            NAME=`basename "$t"`
            # Copy
            # cp "$t" "$BACKUP"/"$NAME"
            # Or pack with pigz
            # pigz -c $t > $BACKUP/$NAME.gz
            echo "Packing $t"
            # Pack with gzip
            gzip -1 -c $t > $BACKUP/$NAME.gz
        done

        # Merge changes back.
        # ---------------------------------------------------\
        BACKUPIMAGES=`virsh domblklist "$DOMAIN" --details | grep 'vd\|hd\|sd'| awk '{print $4}' | grep -v "^-"`
        for t in $TARGETS; do
            virsh blockcommit "$DOMAIN" "$t" --active --pivot >/dev/null
            if [ $? -ne 0 ]; then
                echo "Could not merge changes for disk $t of $DOMAIN. VM may be in invalid state."
                exit 1
            fi
        done

        # Cleanup left over backup images.
        # ---------------------------------------------------\
        for t in $BACKUPIMAGES; do
            rm -f "$t"
        done

        # Dump the configuration information.
        # ---------------------------------------------------\
        virsh dumpxml "$DOMAIN" >"$BACKUP/$DOMAIN.xml"

        # Cleanup older backups.
        # ---------------------------------------------------\
        LIST=`ls -r1 "$BACKUPDOMAIN" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$'`
        i=1
        for b in $LIST; do
            if [ $i -gt "$MAXBACKUPS" ]; then
                echo "Removing old backup "`basename $b`
                rm -rf "$b"
            fi

            i=$[$i+1]
        done
        echo "`date +"%Y-%m-%d_%H-%M-%S"` End backup $DOMAIN" >> $logfile
done

echo "Finished backup"
echo ""
echo "`date +"%Y-%m-%d_%H-%M-%S"` End backup" >> $logfile
