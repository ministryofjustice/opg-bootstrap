#!/bin/bash

################################################### install salt
echo Installing salt
apt-get -y --force-yes install build-essential pkg-config swig
apt-get -y --force-yes install libyaml-0-2 libgmp10
apt-get -y --force-yes install python-dev libyaml-dev libgmp-dev libssl-dev
apt-get -y --force-yes install libzmq3 libzmq3-dev
apt-get -y --force-yes install procps pciutils
apt-get -y --force-yes install python-pip

pip install pyzmq m2crypto pycrypto gitpython psutil boto boto3
pip install salt==${SALT_VERSION}

mkdir -p /etc/salt


##### salt-master

if [  "${IS_SALTMASTER}" == "yes" ]; then
    # let's' install upstart job for salt-master
    cat <<EOF >> /etc/init/salt-master.conf
description "Salt Master"

start on (net-device-up
          and local-filesystems
          and runlevel [2345])
stop on runlevel [!2345]
limit nofile 100000 100000

script
  # Read configuration variable file if it is present
  [ -f /etc/default/$UPSTART_JOB ] && . /etc/default/$UPSTART_JOB

  # Activate the virtualenv if defined
  [ -f $SALT_USE_VIRTUALENV/bin/activate ] && . $SALT_USE_VIRTUALENV/bin/activate

  exec salt-master
end script
EOF
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


##### salt-minion

# let's' install upstart job for salt-minion
cat <<EOF >> /etc/init/salt-minion.conf

description "Salt Minion"

start on (net-device-up
          and local-filesystems
          and runlevel [2345])
stop on runlevel [!2345]

# respawn forever
post-stop exec sleep 10
respawn
respawn limit 10 5

script
  # Read configuration variable file if it is present
  [ -f /etc/default/$UPSTART_JOB ] && . /etc/default/$UPSTART_JOB

  # Activate the virtualenv if defined
  [ -f $SALT_USE_VIRTUALENV/bin/activate ] && . $SALT_USE_VIRTUALENV/bin/activate

  exec salt-minion
end script
EOF

# salt-minon configuration
cat <<EOF >> /etc/salt/minion
log_level: warning
log_level_logfile: all
EOF

# let's set grains
cat <<EOF >> /etc/salt/grains
opg_role: ${OPG_ROLE}
opg_stackname: ${OPG_STACK}
EOF

start salt-minion

# Usually it's safe to run Salt during the first-boot
# stage.  Primarily benefits nodes in the Amazon Auto
# Scaling Group.
salt-call -l debug state.highstate || true
