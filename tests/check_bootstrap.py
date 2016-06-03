#!/usr/bin/env python
#tests:
# check services are running: salt-minion, salt-master, docker
# check salt-master config
# check minionid matches host
# check that extra volumes are mounted
# check nfs storage is configured
# check /etc/environment and /etc/salt/grains are set


import os
import sys
import subprocess

class bootstrapTest(object):

    def __init__(self, end_path, test_type ):
        """

        :param end_path: path of file to check that bootstrap has completed
        :param test_type: type of image being tested. salt or docker are valid values
        """
        self._end_file = end_path
        self.test_type = test_type
        self.services = {
            'salt':
                [ 'salt-minion', 'salt-master' ],
            'docker':
                [ 'salt-minion', 'docker' ]
        }
        self.service_state = {}


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
            check_cmd = [ '/usr/sbin/service', service, 'status' ]
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
    boot = bootstrapTest(end_filename, test_type)
    if boot.complete():
        boot.check_services()
        print boot.service_state
        if not 'failed' in boot.service_state.itervalues():
            MSG = "Bootstrap complete"
        else:
            print "{}\n".format(boot.error)
    print "{}\n".format(MSG)
