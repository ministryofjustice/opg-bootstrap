Testing bootstrap
-----------------

The tests are designed to use ansible to create an instance in AWS using the bootstrap branch that is being tested.  The test will run a script that will determine the validity of the bootstrap process.

Testing profiles
----------------

full - test bootstrap on docker AMI image.
base - test bootstrap on base AMI image.


Running tests
-------------
The variable **SUBNET_ID** is required to be in the environment, or passed to the make command ie _make test SUBNET_ID=subnet-xxxxx_
The playbook will terminate the instances if the variable **cleanup** is set to **'yes'** in the make command.

Run tests by using the [jenkins job](https://jenkins.service.opg.digital/job/OPG/job/opg-bootstrap-test/) or from the command line with make
```
opg-bootstrap$ cd tests
tests$ make all SUBNET_ID=subnet-xxxxxx cleanup=yes
```

build targets:

* _check_ - run shellcheck lint tests on modules
* _test_ - run lint and syntax checks on ansible playbooks and shell scripts
* _build_ - run playbook
* _debug_ - run playbook but with more verbose logging

Security
--------
A new keypair is generated on every run and is by default set to use the _~/.ssh/id_rsa.pub_ file.  If this file is missing the playbook will fail. The file location can be changed by setting the **ssh_pub_key_file** variable for ansible.