#!/bin/bash

function module()
{
    local module_path=$1
    if [ ! -e ${module_path} ]; then
        echo Downloading ${module_path}
        mkdir -p modules
        curl -so modules/salt.sh https://raw.githubusercontent.com/ministryofjustice/opg-bootstrap/master/README.md
    fi
    echo Loading ${module_path}
    source ${module_path}
}

module modules/salt.sh
