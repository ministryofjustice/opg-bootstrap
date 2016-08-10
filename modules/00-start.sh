#!/usr/bin/env bash
set -x
echo "BEGIN: $(TZ=UTC date)"
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
export DEBIAN_FRONTEND=noninteractive
readonly EC2_METADATA_URL='http://169.254.169.254/latest/meta-data'

#Setup hosts file
# https://aws.amazon.com/premiumsupport/knowledge-center/linux-static-hostname/
echo "Updating hostname"
# domain name and resolv.conf ar managed through dhcp
IP=$(curl -s "${EC2_METADATA_URL}/local-ipv4")
TRUNC_INSTANCE_ID=$(curl -s "${EC2_METADATA_URL}/instance-id" | sed -e 's/^i-//')
if [[ -v OPG_ROLE ]]
then
  NEW_HOSTNAME=${OPG_ROLE}-${TRUNC_INSTANCE_ID}
else
  NEW_HOSTNAME=${TRUNC_INSTANCE_ID}
fi
echo "${IP} ${NEW_HOSTNAME} ${OPG_ROLE}" >> /etc/hosts
echo "${NEW_HOSTNAME}" > /etc/hostname
hostname ${NEW_HOSTNAME}
service rsyslog restart

service rsyslog restart

#update apt-cache
apt-get update

# Make sure files are 644 and directories are 755.
umask 022


######################### salt stop
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



############################ docker stop
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

#add OPG_ variables to /etc/environment to make them available outside of config mgmt
cat <<EOF >> /etc/environment
OPG_STACKNAME="${OPG_STACKNAME}"
OPG_ROLE="${OPG_ROLE}"
OPG_PROJECT="${OPG_PROJECT}"
OPG_ENVIRONMENT="${OPG_ENVIRONMENT}"
OPG_ENV="${OPG_STACKNAME}"
OPG_SHARED_SUFFIX="${OPG_SHARED_SUFFIX}"
OPG_DOMAIN="${OPG_DOMAIN}"
EOF

#update dhcp settings to include stack search domain

if grep -q "^prepend domain-name" /etc/dhcp/dhclient.conf
then
    sed -i 's/^prepend domain-name.*/prepend domain-name " '${OPG_STACKNAME}'.internal ;"/' /etc/dhcp/dhclient.conf
else
    echo "prepend domain-name  \"${OPG_STACKNAME}.internal \";" >> /etc/dhcp/dhclient.conf
fi

#make runtime change to affect above config
sed -i 's/^search/search '${OPG_STACKNAME}'.internal/' /etc/resolv.conf

