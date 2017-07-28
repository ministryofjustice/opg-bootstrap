#!/usr/bin/env bash
set -x
echo "BEGIN: $(TZ=UTC date)"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
export DEBIAN_FRONTEND=noninteractive
readonly EC2_METADATA_URL='http://169.254.169.254/latest/meta-data'

########################################################
# Update hostname
# resolv.conf is managed via DHCP
IP=$(curl -s ${EC2_METADATA_URL}/local-ipv4)
ID=$(curl -s ${EC2_METADATA_URL}/instance-id)
HOSTNAME="${OPG_ROLE}-${ID}"
echo "Updating hostname to: ${HOSTNAME}"

echo "${IP} ${HOSTNAME} ${OPG_ROLE}" >> /etc/hosts
echo $HOSTNAME | tee \
    /proc/sys/kernel/hostname \
    /etc/hostname
hostname -F /etc/hostname

# Restart rsyslog to pickup new hostname
service rsyslog restart

# Make sure files are 644 and directories are 755.
umask 022

if [[ "${USE_SALT}" == "yes" ]]
then
################################################### salt stop
    echo "Ensuring salt is stopped"
    # Need to stop Salt services.
    for s in salt-{minion,master}; do
        if [[ -f /etc/init/${s}.conf ]]; then
            service $s stop || true

            # Stop with extreme prejudice.
            if pgrep -f $s &>dev/null; then
                pkill -9 -f $s
            fi

            # Purge any keys and/or SSL certificates
            # that might have linger behind.
            rm -rf /etc/salt/pki/${s##*-}
        fi
    done

    # Make sure that Minion will pick his new ID to
    # advertise use after the new host name was set.
    rm -f /etc/salt/minion_id

    # Make sure to remove any cache left by Salt, etc.
    rm -rf /var/{cache,log,run}/salt/*
fi


if [[ "${USE_DOCKER}" == "yes" ]]
then
################################################### docker stop
    echo "Ensuring docker is stopped"
    # Need to stop Docker in order to make sure that
    # the /srv/docker is not in use, as often "aufs"
    # and "devicemapper" drivers will be active on
    # boot causing "device or resource busy" errors.
    if docker --version &>/dev/null; then
        service docker stop || true

        # Disable the Docker service and switch it
        # off completely if requested to do so.
        if [[ "${DISABLE_DOCKER}" == 'yes' ]]; then
            for f in /etc/init/docker.conf /etc/init.d/docker; do
                dpkg-divert --rename $f
            done

            update-rc.d -f docker disable || true
        else
            export DOCKER='yes'
        fi
    fi
fi

#set default bash prompt
echo "Setting custom bash prompt"
cat <<'EOF' > /etc/profile.d/bash-prompt.sh

if [[ ${EUID} == 0 ]]
then
        PS1="${PS1}\w #\[\033[00m\]"
else
        PS1="${PS1}\w $\[\033[00m\]"
fi
EOF
OPG_STACK=$(echo "${OPG_STACK}"| tr -d '[:digit:]')
if [[ "${OPG_STACK}" =~ ^production ]]
then
    sed -i "1s/^/PS1=\"\\\[\\\033[01;31m\\\](${OPG_STACK}) \\\u@${OPG_ROLE}:\"\n/" /etc/profile.d/bash-prompt.sh
else
    sed -i "1s/^/PS1=\"\\\[\\\033[01;34m\\\](${OPG_STACK}) \\\u@${OPG_ROLE}:\"\n/" /etc/profile.d/bash-prompt.sh
fi

echo "Install support packages"
apt-get -y -qq update
apt-get -y -qq install joe git awscli


# SET MTU to 1500
# As required by ATOS
ip link set dev eth0 mtu 1500
