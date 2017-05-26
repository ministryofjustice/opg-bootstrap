#!/bin/bash

if grep -q '\W/srv\W*btrfs' /etc/fstab
then
    echo "DOCKER_OPTS=\"\${DOCKER_OPTS} -s btrfs\"" >> /etc/default/docker
fi

service docker restart
