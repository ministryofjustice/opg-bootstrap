#!/bin/bash

function module()
{
    local module_path=$1
    if [ ! -e ${module_path} ]; then
        echo Downloading ${module_path}
        mkdir -p modules
        curl -so ${module_path} https://raw.githubusercontent.com/ministryofjustice/opg-bootstrap/master/${module_path}
    fi
    echo Loading ${module_path}
    source ${module_path}
}

module modules/salt.sh
module modules/docker.sh
module modules/volumes.sh
