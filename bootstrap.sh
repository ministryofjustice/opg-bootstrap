#!/bin/bash
#let's log the output
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

function module()
{
    local module_path=$1
    if [ ! -e ${module_path} ]; then
        echo ${module_path}: Downloading
        mkdir -p modules
        curl -so ${module_path} https://raw.githubusercontent.com/ministryofjustice/opg-bootstrap/master/${module_path}
    fi
    echo ${module_path}: Loading
    source ${module_path}
}

readonly IS_SALTMASTER=${is_saltmaster:-no}
readonly HAS_DATA_STORAGE=${has_data_storage:-no}
readonly OPG_ROLE=${opg_role:-default}

readonly DOCKER_COMPOSE_VERSION=${docker_compose_version}
readonly SALT_VERSION=${salt_version}

module modules/00-start.sh
module modules/10-volumes.sh
module modules/20-salt.sh
module modules/30-docker.sh
module modules/99-end.sh
