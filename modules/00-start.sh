echo "BEGIN: `TZ=UTC date`"

# fail on 1st failure
set -e

export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
export DEBIAN_FRONTEND=noninteractive
readonly EC2_METADATA_URL='http://169.254.169.254/latest/meta-data'

# Make sure files are 644 and directories are 755.
umask 022


echo Updating hostname
# domain name and resolv.conf ar managed through dhcp
IP=$(curl -s ${EC2_METADATA_URL}/local-ipv4)
AZ=$(ec2metadata --availability-zone | awk -F "-" '{print $3}')
AWS_HOSTNAME=`hostname`
HOSTNAME="${OPG_ROLE}-${AWS_HOSTNAME}-${AZ}"

echo "${IP} ${HOSTNAME} ${ROLE} ${AWS_HOSTNAME}" >> /etc/hosts
echo $HOSTNAME | tee \
    /proc/sys/kernel/hostname \
    /etc/hostname
hostname -F /etc/hostname

# let's restart rsyslog to catchup with new hostname
service rsyslog restart


### AWS
echo Install few packages
# install shared tools
apt-get -y --force-yes update
apt-get -y --force-yes install joe git awscli dpkg-dev libssl-dev python-m2crypto
