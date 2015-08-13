#!/bin/bash

################################################### hostname install salt
echo Installing salt
apt-get -y --force-yes install build-essential pkg-config swig
apt-get -y --force-yes install libyaml-0-2 libgmp10
apt-get -y --force-yes install python-dev libyaml-dev libgmp-dev libssl-dev
apt-get -y --force-yes install libzmq3 libzmq3-dev
apt-get -y --force-yes install procps pciutils
apt-get -y --force-yes install python-pip

pip install pyzmq m2crypto pycrypto gitpython psutil boto boto3
pip install salt==${SALT_VERSION}

curl -o /etc/init/salt-minion.conf https://raw.githubusercontent.com/saltstack/salt/develop/pkg/salt-minion.upstart
mkdir -p /etc/salt
touch /etc/salt/minion
cat <<EOF >> /etc/salt/grains
opg-role: ${OPG_ROLE}
EOF

start salt-minion

if [  "${IS_SALTMASTER}" == "yes" ]; then
    curl -o /etc/init/salt-master.conf https://raw.githubusercontent.com/saltstack/salt/develop/pkg/salt-master.upstart
    cat <<EOF >> /etc/salt/master
auto_accept: True
file_roots:
  base:
    - /srv/salt
    - /srv/salt/_libs
    - /srv/salt-formulas
state_output: changes
EOF
    start salt-master
fi
