# opg-bootstrap



ensure we get rid of all apt-get clean



provisions vm with:
- salt
- docker

/srv (btrfs: as merge of all available ephemeral volumes)
/data (ext4: as attached ebs volume)


assumes that ebs volume is attached at /dev/sdh or /dev/xvdh
