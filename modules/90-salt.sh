#!/bin/bash
set -e

mkdir -p /etc/salt

[[ -f /etc/salt/minion_id ]] && rm -f /etc/salt/minion_id
[[ -f /etc/salt/pki/minion/minion.pem ]] && rm -f /etc/salt/pki/minion/minion.pem
[[ -f /etc/salt/pki/minion/minion.pub ]] && rm -f /etc/salt/pki/minion/minion.pub

##### salt-master

if [  "${IS_SALTMASTER}" == "yes" ]; then
    #install the salt-master package from the salt repo in the ami
    apt-get -y update
    apt-get -y install salt-master salt-api salt-ssh
    #fix 14.04 issue with upstart and sysv start scripts
    [[ -f /etc/init/sal-master.conf && -f /etc/init.d/salt-master ]] && echo manual >> /etc/init/salt-master.override

    cat <<'EOF' >> /etc/salt/master
auto_accept: True
hash_type: sha256
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


    update-rc.d defaults salt-master || systemctl enable salt-master
    start salt-master || systemctl start salt-master
fi

# salt-minon configuration
cat <<'EOF' >> /etc/salt/minion
log_level: warning
log_level_logfile: all
startup_states: highstate
EOF

# let's set grains
AWS_INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

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
    update-rc.d -f salt-minion remove 2>/dev/null || systemctl disable salt-minion
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
    # Start salt minion
    update-rc.d salt-minion defaults || systemctl enable salt-minion
    service salt-minion restart
fi
