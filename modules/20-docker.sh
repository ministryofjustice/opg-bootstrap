#!/bin/bash

if grep -q '\W/srv\W*btrfs' /etc/fstab; then
    # Use "btrfs" over "aufs" by default as the solution
    # for the Copy-on-Write (CoW) file system.
    echo "DOCKER_OPTS=\"\${DOCKER_OPTS} -s btrfs\"" >> /etc/default/docker
else
    echo "DOCKER_OPTS=\"\${DOCKER_OPTS} --storage-opt dm.no_warn_on_loop_devices=true\"" >> /etc/default/docker
fi

service docker restart
aws