#!/bin/bash -ex
#let's log the output
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

function download()
{
    #try downloading a file for 5 mins
    #if you want to use a branch of the bootstrap repo, set the BS_BRANCH variable in userdata
    local module_path="${1}"
    local retry_count_down=30
    while ! wget --no-verbose --retry-connrefused --random-wait -O "${module_path}" "https://raw.githubusercontent.com/ministryofjustice/opg-bootstrap/${BS_BRANCH:-v0.1.0}/${module_path}" && [ ${retry_count_down} -gt 0 ] ; do
        retry_count_down=$((retry_count_down - 1))
        sleep 10
    done
}

function module()
{
    local module_path="${1}"
    if [ ! -e "${module_path}" ]; then
        echo "${module_path}: Downloading"
        mkdir -p modules
        download "${module_path}"
    fi
    echo "${module_path}: Loading"
    source "${module_path}"
}

module modules/00-start.sh

# don't format volumes using cloud-init on 14.04
# 16.04 will be sorted later on.
if grep 16.04 /etc/os-release ; then
    module modules/10-volumes.sh
    [[ "${USE_DOCKER}" == "no" ]] || module modules/20-docker.sh
fi

[[ "${USE_SALT}" = "no" ]] || module modules/90-salt.sh
module modules/99-end.sh
