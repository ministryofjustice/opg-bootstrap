echo "BEGIN: `TZ=UTC date`"

# fail on 1st failure
set -e

export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
export DEBIAN_FRONTEND=noninteractive
readonly EC2_METADATA_URL='http://169.254.169.254/latest/meta-data'

# Make sure files are 644 and directories are 755.
umask 022


################################################### salt stop
echo Ensuring salt is stopped
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


################################################### docker stop
echo Ensuring docker is stopped
# Need to stop Docker in order to make sure that
# the /srv/docker is not in use, as often "aufs"
# and "devicemapper" drivers will be active on
# boot causing "device or resource busy" errors.
if docker --version &>/dev/null; then
    service docker stop || true

    # Disable the Docker service and switch it
    # off completely if requested to do so.
    if [[ $DISABLE_DOCKER == 'yes' ]]; then
        for f in /etc/init/docker.conf /etc/init.d/docker; do
            dpkg-divert --rename $f
        done

        update-rc.d -f docker disable || true
    else
        DOCKER='yes'
    fi
fi



################################################### hostname
echo Updating hostname
# domain name and resolv.conf ar managed through dhcp
IP=$(curl -s ${EC2_METADATA_URL}/local-ipv4)
AWS_HOSTNAME=`hostname`
HOSTNAME="${OPG_ROLE}-${AWS_HOSTNAME}"

echo "${IP} ${HOSTNAME} ${OPG_ROLE} ${AWS_HOSTNAME}" >> /etc/hosts
echo $HOSTNAME | tee \
    /proc/sys/kernel/hostname \
    /etc/hostname
hostname -F /etc/hostname

# let's restart rsyslog to catchup with new hostname
service rsyslog restart


### AWS
echo Install few packages
# install shared tools
apt-get -y --force-yes install joe git awscli
apt-get -y --force-yes update
