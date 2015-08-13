#!/bin/bash



function fstype()
# returns on stdout a filesystem type
#  volume can be unmounted)
{
    blkid -o value -s TYPE $1
}

echo Cleanup /etc/fstab
# Remove anything that looks like a floppy drive.
#TODO: Is it needed
sed -i -e \
    '/^.\+fd0/d;/^.\*floppy0/d' \
    /etc/fstab

# Re-format /etc/fstab to fix whitespaces there.
#TODO: Is it needed
sed -i -e \
    '/^#/!s/\s\+/\t/g' \
    /etc/fstab

# Remove entries for the time being.
sed -i -e \
    '/^.*\/mnt/d;/^.*\/srv/d' \
    /etc/fstab


echo Scaning SCSI bus to look for new devices
for b in /sys/class/scsi_host/*/scan; do
    echo '- - -' > $b
done

echo Refreshing partition table for each block device.
for b in $(lsblk -dno NAME | awk '!/(sr.*|mapper)/ { print $1 }'); do
    echo "Refreshing: ${b}"
    sfdisk -R /dev/${b} 2> /dev/null || true
done


echo Fetching service storage configuration - ephemeral
# Select correct device for the extra attached ephemeral
# and ebs volumes - volume (usually mounted under the
# /srv mount point).
SERVICE_STORAGE='no'
SERVICE_STORAGE_DEVICES=()
SERVICE_STORAGE_DEVICES_COUNT=0

# Get the list of Ephemeral devices from Amazon ...
EPHEMERALS=($(
    curl -s ${EC2_METADATA_URL}/block-device-mapping/ | \
        awk '/ephemeral[[:digit:]]+/ { print }'
))

# ... and validate whether a particular device actually
# exists which is not always the case, as sometimes the
# meta-data service would return data where no actual
# device is present.
for d in "${EPHEMERALS[@]}"; do
    DEVICE=$(curl -s ${EC2_METADATA_URL}/block-device-mapping/${d})
    if [[ -n $DEVICE ]]; then
        # Try to detect the device, taking into
        # the account different naming scheme
        # e.g., /dev/sdb vs /dev/xvdb, etc.
        if [[ ! -b /dev/${DEVICE} ]]; then
            DEVICE=${DEVICE/sd/xvd}
            [[ -b /dev/${DEVICE} ]] || continue
        fi
    fi

    # Got a device? Great.
    SERVICE_STORAGE='yes'
    SERVICE_STORAGE_DEVICES+=( "/dev/${DEVICE}" )
done

# Make sure to sort the devices list.
SERVICE_STORAGE_DEVICES=($(
    printf '%s\n' "${SERVICE_STORAGE_DEVICES[@]}" | sort
))

# How may devices do we have at our disposal? This is
# needed to setup RAID (stripe) later.
SERVICE_STORAGE_DEVICES_COUNT=${#SERVICE_STORAGE_DEVICES[@]}

# Make sure "noop" scheduler is set. Alternatively,
# the "deadline" could be used to potentially reduce
# I/O latency in some cases. Also, set read-ahead
# value to double the default.
for d in "${SERVICE_STORAGE_DEVICES[@]}"; do
    echo 'noop' > /sys/block/${d##*/}/queue/scheduler
    blockdev --setra 512 $d
done


echo Ensuring service volumes are unmounted
if [[ $SERVICE_STORAGE == 'yes' ]]; then
    # Make sure that /mnt and /srv are not mounted.
    for d in /mnt /srv; do
        # Nothing of value should be there in these directories.
        if [[ -d $d ]]; then
            umount -f $d || true
            rm -rf ${d}/*
        else
            mkdir -p $d
        fi

        chown root:root $d
        chmod 755 $d
    done

    # Make sure that attached volume really
    # is not mounted anywhere.
    for d in "${SERVICE_STORAGE_DEVICES[@]}"; do
        if grep -q $d /proc/mounts &>/dev/null; then
            # Sort by length, in order to unmount longest path first.
            grep $d /proc/mounts | awk '{ print length, $2 }' | \
                sort -gr | cut -d' ' -f2- | xargs umount -f || true
        fi
    done

    # Should not be mounted at this stage.
    umount -f /tmp || true

    # Wipe any old file system signature, just in case.
    for d in "${SERVICE_STORAGE_DEVICES[@]}"; do
        wipefs -a$(wipefs -f &>/dev/null && echo 'f') $d
    done
fi


# Add support for the Copy-on-Write (CoW) file system
# using the "btrfs" over the default "aufs".
if [[ $SERVICE_STORAGE == 'yes' ]]; then

    # Make sure to install dependencies if needed.
    if ! dpkg -s btrfs-tools &>/dev/null; then
        apt-get -y --force-yes --no-install-recommends install btrfs-tools
    fi

    # Grab first device (to be used when mounting).
    DEVICE=${SERVICE_STORAGE_DEVICES[0]}

    # Create RAID0 if there is more than one device.
    if (( $SERVICE_STORAGE_DEVICES_COUNT > 1 )); then
        mkfs.btrfs -L '/srv' -d raid0 -f \
            $(printf '%s\n' "${SERVICE_STORAGE_DEVICES[@]}")
    else
        mkfs.btrfs -L '/srv' -f $DEVICE
    fi

    # Add extra volume.
    echo "$DEVICE /srv btrfs defaults,noatime,recovery,space_cache,compress=lzo,nobootwait,comment=cloudconfig 0 2" >> /etc/fstab

    mount /srv
    btrfs filesystem show /srv

    if (( $SERVICE_STORAGE_DEVICES_COUNT > 1 )); then
        # Make sure to initially re-balance stripes.
        btrfs filesystem balance /srv
    fi

    # Nothing of value should be there in these directories.
    for d in /var/lib/docker /srv/docker; do
        if [[ -d $d ]]; then
            umount -f $d || true
            rm -rf ${d}/*
        else
            mkdir -p $d
        fi

        chown root:root $d
        chmod 755 $d
    done

    # Move /tmp to /srv/tmp - hope, that there is not a lot
    # of data present in under /tmp already ...
    mkdir -p /srv/tmp
    chown root:root /srv/tmp
    chmod 1777 /srv/tmp

    # We need to use /var/tmp this time.
    rsync -avr -T /var/tmp /tmp/ /srv/tmp

    # Clean and correct permission.
    rm -rf /tmp/*
    chown root:root /tmp
    chmod 1777 /tmp

    # A bind-mount for the surrogate /tmp directory.
    echo "/srv/tmp /tmp none bind 0 2" >> /etc/fstab

    # A bind-mount for the Docker root directory.
    echo "/srv/docker /var/lib/docker none bind 0 2" >> /etc/fstab

    # Mount bind-mounts, etc.
    for d in /srv/{tmp,docker}; do
        mount $d
    done

fi


echo Fetching attached volume configuration
# Select correct device for the extra attached EBS-backed
# volume (usually mounted under the /data mount point).
DATA_STORAGE='no'
DATA_STORAGE_DEVICE='/dev/xvdh'
if [[ $HAS_DATA_STORAGE == 'yes' ]]; then
    # Keep track of number of attempts.
    COUNT=0
    while [[ $DATA_STORAGE == 'no' ]]; do
        # Keep waiting up to 5 minutes (extreme case) for the volume.
        if (( $COUNT >= 60 )); then
            echo "Unable to find device $DATA_STORAGE_DEVICE, volume not attached?"
            break
        fi

        for d in /dev/{xvdh,sdh}; do
            if [[ -b $d ]]; then
                DATA_STORAGE='yes'
                DATA_STORAGE_DEVICE=$d
                break
            fi
        done

        COUNT=$(( $COUNT + 1 ))
        sleep 5
    done
fi

if [[ $DATA_STORAGE == 'yes' ]]; then
    # Make sure that /data is not mounted.
    if [[ -d /data ]]; then
        umount -f /data || true
    else
        mkdir -p /data
    fi

    chown root:root /data
    chmod 755 /data

    # Setup the /data mount point on a solid file system (EXT4).
    # If EBS is already formatted and has file /data/.opg-keep
    DATA_STORAGE_FORMAT='no'
    if mount ${DATA_STORAGE_DEVICE} /data; then
        if [[ -e /data/.opg-keep ]]; then
            # an edge case when we attache volume that was already provisioned
            # just keep it
            DATA_STORAGE_CURRENT_FSTYPE=$(fstype ${DATA_STORAGE_DEVICE})
            echo "${DATA_STORAGE_DEVICE} /data ${DATA_STORAGE_CURRENT_FSTYPE} defaults,noatime 0 2" >> /etc/fstab
            DATA_STORAGE_FORMAT='no'
        else
            DATA_STORAGE_FORMAT='yes'
            #TODO: trigger ebs snapshot before we format it
            umount /data
        fi
    else
        DATA_STORAGE_FORMAT='yes'
    fi

    if [[ $DATA_STORAGE_FORMAT == 'yes' ]]; then
        echo "Formatting ${DATA_STORAGE_DEVICE}"
        mkfs.ext4 ${DATA_STORAGE_DEVICE}
        echo "${DATA_STORAGE_DEVICE} /data ext4 defaults,noatime 0 2" >> /etc/fstab
        mount /data
        touch /data/.opg-keep
        chattr +i /data/.opg-keep
    fi
fi
