#!/bin/bash
set -e

################################################### install salt
echo "Installing salt"
apt-get -y -qq install build-essential pkg-config swig
apt-get -y -qq install libyaml-0-2 libgmp10
apt-get -y -qq install python-dev libyaml-dev libgmp-dev libssl-dev
apt-get -y -qq install libzmq3 libzmq3-dev python-m2crypto
apt-get -y -qq install procps pciutils
apt-get -y -qq install python-pip

#upgrade pip to latest version
pip install --upgrade pip

pip install pyzmq pycrypto gitpython psutil boto boto3

if [[ "x${SALT_VERSION}" == "x" ]]
then
    pip install --upgrade salt
else
    pip install --upgrade salt=="${SALT_VERSION}"
fi

mkdir -p /etc/salt


##### salt-master

if [  "${IS_SALTMASTER}" == "yes" ]; then
    # let's' install upstart job for salt-master
    cat <<'EOF' >> /etc/init/salt-master.conf
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

    cat <<'EOF' >> /etc/salt/master
auto_accept: True
file_roots:
  base:
    - /srv/salt
    - /srv/salt/_libs
    - /srv/salt-formulas
    - /srv/reactor
state_output: changes

##PILLAR_ROOT_TOKEN_BEGIN##
##PILLAR_ROOT_TOKEN_END##

presence_events: True

reactor:
  - 'salt/auth':
    - /etc/salt/reactor/auth.sls
  - 'salt/custom/*':
    - 'salt://custom-reactors.sls'

EOF

    mkdir -p /etc/salt/reactor
    cat <<'EOF' >> /etc/salt/reactor/auth.sls
{# minion failed to authenticate -- remove accepted key #}
{% if not data['result'] %}
minion_remove:
  wheel.key.delete:
    - match: {{ data['id'] }}
{% endif %}

{# minion is sending new key -- accept this key -- duplicate with auto_accept #}
{% if 'act' in data and data['act'] == 'pend' %}
minion_add:
  wheel.key.accept:
    - match: {{ data['id'] }}
{% endif %}
EOF

    mkdir -p /srv/reactor/
    cat <<'EOF' >> /srv/reactor/custom-reactors.sls
{# When a remote highstate is called #}
{%  if data['tag'] == 'salt/custom/start_highstate' %}
start_highstate:
  local.state.highstate:
    - tgt: '*'

{% endif %}
EOF


    start salt-master
fi


##### salt-minion

# let's' install upstart job for salt-minion if we are running with a master
if [ "${SALT_STANDALONE}" != "yes" ]
then
    cat <<'EOF' >> /etc/init/salt-minion.conf

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
  
  # Force minion to rebuild key on each boot so that after salt-master failure all we need is to reboot VMs one by one
  rm -Rf /etc/salt/pki/minion

  exec salt-minion
end script

EOF
fi

# salt-minon configuration
cat <<'EOF' >> /etc/salt/minion
log_level: warning
log_level_logfile: all
startup_states: highstate
EOF

# let's set grains
AWS_INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`

cat <<EOF >> /etc/salt/grains
opg_role: ${OPG_ROLE}
opg_stackname: ${OPG_STACKNAME}
opg_project: ${OPG_PROJECT}
opg_stack: "${OPG_STACK}"

opg_environment: ${OPG_ENVIRONMENT}
opg_account_id: "${OPG_ACCOUNT_ID}"
opg_shared_suffix: "${OPG_SHARED_SUFFIX}"
opg_domain: "${OPG_DOMAIN}"

opg_aws_instance_id: "${AWS_INSTANCE_ID}"
EOF

#start salt minion service when not in standalone mode
if [[ "${SALT_STANDALONE}" == "yes" ]]
then
    #remove salt-minion service
    update-rc.d -f salt-minion remove 2>/dev/null
    # The salt formulae, pillars, etc are held in an s3 bucket.
    aws --region=eu-west-1 s3 sync "${SALT_S3_PATH}" /srv/
    #add the root dirs to the salt config
    cat <<EOF >> /etc/salt/minion
file_roots:
  base:
    - /srv/salt
    - /srv/salt/_libs
    - /srv/salt-formulas
EOF
    salt-call --local state.highstate
else
    # Check whether there is a connectivity with the
    # Salt Master by checking both ports on which it
    # should listen (4505 and 4506).
    for n in {1..10}; do
        MASTER_RESPONSES=()

        for p in 4505 4506; do
            if nc -z -w 3 salt $p &> /dev/null; then
                MASTER_RESPONSES+=( $p )
            fi
        done

        # Break from loop if both ports responding
        (( ${#MASTER_RESPONSES[@]} >= 2 )) && break

        sleep 1
    done

    # Start salt minion
    start salt-minion

fi
