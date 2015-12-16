#!/bin/bash

# install docker
echo Installing Docker
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list
apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/docker.list
apt-get install -y docker-engine=${DOCKER_ENGINE_VERSION:-"1.9.1-*"}

curl -L https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION:-"1.5.2"}/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "DOCKER_OPTS=\"\${DOCKER_OPTS} --ipv6=false --log-driver=syslog\"" >> /etc/default/docker

if grep -q '\W/srv\W*btrfs' /etc/fstab; then
    # Use "btrfs" over "aufs" by default as the solution
    # for the Copy-on-Write (CoW) file system.
    echo "DOCKER_OPTS=\"\${DOCKER_OPTS} -s btrfs\"" >> /etc/default/docker

fi

service docker restart
