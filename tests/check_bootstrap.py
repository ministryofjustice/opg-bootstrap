#!/usr/bin/env python
#tests:
# check services are running: salt-minion, salt-master, docker
# check salt-master config
# check minionid matches host
# check that pillarenv is set on minion
# check that extra volumes are mounted
# check nfs storage is configured
# check /etc/environment and /etc/salt/grains are set


import os
import sys
import subprocess


class BootstrapTest(object):

    def __init__(self, end_path, t_type):
        """

        :param end_path: path of file to check that bootstrap has completed
        :param test_type: type of image being tested. salt or docker are valid values
        """
        self._end_file = end_path
        self.test_type = t_type
        self.services = {
            'salt':
                ['salt-minion', 'salt-master'],
            'docker':
                ['salt-minion', 'docker']
        }
        self.service_state = {}

    def has_pillarenv(self):
        with open('/etc/salt/grains', 'r') as f:
            stack_name = "{}".format("".join([s for s in f.readlines() if 'opg_stackname' in s]))
        opg_stack = stack_name.split(':')
        with open('/etc/salt/minion', 'r') as f:
            stack_name = "{}".format("".join([s for s in f.readlines() if 'pillarenv'in s]))
        pillar_env = stack_name.split(':')
        return opg_stack[1] == pillar_env[1]


    def complete(self):
        """
        Return true if file exists
        :param _end_file: filename to check for as mark of completion
        :return:
        """
        try:
            return os.path.isfile(self._end_file)
        except IOError:
            return False

    def check_services(self):
        """
        Set value of service_state dict based on commands run
        """
        for service in self.services[test_type]:
            use_systemd = os.path.exists('/etc/systemd/')
            check_cmd = ['/usr/sbin/service', service, 'status']
            try:
                print "{}\n".format(check_cmd)
                svc = subprocess.check_output(check_cmd)
            except subprocess.CalledProcessError as e:
                self.error = e.output
                svc = "Error"
            except OSError as oe:
                self.error = oe.strerror
                svc = "Error"
            if 'running' in svc:
                self.service_state[service] = 'passed'
            else:
                self.service_state[service] = 'failed'

    def check_salt_config(self):
        return True


if __name__ == "__main__":
    if len(sys.argv) == 2:
        test_type = sys.argv[1]
    else:
        test_type = 'salt'
    print "Running tests for " + test_type
    # end_filename = 'hosts'
    end_filename = '/var/run/opg-user-data-done'
    MSG = 'Bootstrap failed'
    boot = BootstrapTest(end_filename, test_type)
    if boot.complete():
        boot.check_services()
        print boot.service_state
        if not 'failed' in boot.service_state.itervalues():
            MSG = "Bootstrap complete"
        else:
            print "{}\n".format(boot.error)
    assert boot.has_pillarenv()
    print "{}\n".format(MSG)
