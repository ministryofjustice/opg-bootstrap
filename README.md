opg-bootstrap
-------------
A pluggable AMI user-data script.
Although bootstrap.sh is in terraform template language, there is nothing preventing from using it directly 
from CloudFormation.

Provisions VM with:
- salt
- docker

Setups filesystem:
- /srv (btrfs: as raid0 of all available ephemeral volumes - only if available)
- /data (nfs or attached ebs volume(ext4) - only if needed)


configuration
=============
- USE_SALT - whether to install salt
- SALT_STANDALONE - configure to run without salt master
- IS_SALTMASTER - is host a salt master or minion
- SALT_VERSION - what salt version to install
- SALT_S3_PATH - The s3 path for masterless salt operation
- HAS_DATA_STORAGE - have you attached ebs volume?
- USE_DOCKER - whether to install docker
- DOCKER_ENGINE_VERSION - docker engine version to install (will install latest version if not set)
- DOCKER_COMPOSE_VERSION - what docker compose version to install (will install latest version if not set)
- DOCKER_NFS_DATA - use nfs to persist container data.
- OPG_ROLE - sets opg-role grain to this value (to be deprecated in favour to aws tags)
- OPG_STACK - sets opg-stack grain to this value

attached volume
===============
Assumes that ebs volume is attached at /dev/sdh or /dev/xvdh.  If this is a node for and ECS cluster, there will be an NFS mount on /nfsdata.


how to use it
=============
1st you need to render bootstrap.sh using terraform and pass all required variables.
I.e.:
```
variable "salt_version" {
    # used to install salt with pip
    default = "2015.5.6"
}

variable "docker_engine_version" {
    # as docker engine is installed using apt-get, you can leverage the "-*" form
    default = "1.9.1-*"
}

variable "docker_compose_version" {
    default = "1.5.2"
}

resource "template_file" "user_data_monitoring" {
    filename = "bootstrap_dev.sh"
    vars {
        is_saltmaster = "no"
        has_data_storage = "yes"
        opg_role = "monitoring"
        salt_version = "${var.salt_version}"
        docker_engine_version = "${var.docker_engine_version}"
        docker_compose_version = "${var.docker_compose_version}"
    }
}
```

Then you can pass user_data to a new EC2 instance.
I.e.:
```
resource "aws_instance" "monitoring" {
    ami = "${var.ami}"
    instance_type = "r3.large"
    key_name = "${var.ssh_key_name}"
    monitoring = true
    tags {
        Name = "monitoring.${var.stack}.${var.domain}"
        Stack = "${var.stack}"
    }
    subnet_id = "${aws_subnet.private1a.id}"

    vpc_security_group_ids = [
        "${aws_security_group.default.id}",
        "${aws_security_group.salt_minion.id}",
        "${aws_security_group.jumpbox_client.id}",
        "${aws_security_group.monitoring.id}"
    ]

    user_data = "${template_file.user_data_monitoring.rendered}"
}
```

When host boots it will call user_data script.
Our user_data script is only a thin seed allowing to download all required boot scripts.
That way you can alter your user_data script and i.e. remove salt part, or docker part, or add additional module.

`bootstrap.sh` is only an example of user_data script. 


todo
====
- Auto Scaling groups support - check what is missing
- Split each script into install/configure so that we can ignore the install on prebuilt amis
- I can see a place for salt configuring part to skip setting up opg-role (if we have roles as tags)
- Generate hostname based on role in tag
