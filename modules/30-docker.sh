#!/bin/bash

# install docker
echo Installing Docker
apt-get install -y wget
wget -qO- https://get.docker.com/ | sh
curl -L https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "DOCKER_OPTS=${DOCKER_OPTS} --ipv6=false" >> /etc/default/docker

if grep -q '\W/srv\W*btrfs' /etc/fstab; then
    # Use "btrfs" over "aufs" by default as the solution
    # for the Copy-on-Write (CoW) file system.
    echo "DOCKER_OPTS=\"\${DOCKER_OPTS} -s btrfs\"" >> /etc/default/docker

fi

service docker restart
