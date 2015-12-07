#!/usr/bin/env python

import boto.utils, boto.ec2
import salt.client
import string
import sys

# Exit codes
EXIT_ALL_OK=0
EXIT_BOTO_GET_METADATA_INSTANCE=110
EXIT_BOTO_GET_METADATA_AZ=120
EXIT_BOTO_CONNECT_REGION_FAIL=130
EXIT_BOTO_GET_ALL_INSTANCES_FAIL=140
EXIT_SALT_CLIENT_FAIL=150
EXIT_SALT_GRAINS_SETVAL_FAIL=160

# Boto timeout values
timeout=10
retries=2

def die(code):
  if code > 0:
    print("Exit with code " + str(code))
  sys.exit(code)

try:
  instance_id = boto.utils.get_instance_metadata(timeout=timeout, num_retries=retries)['instance-id']
except:
  die(EXIT_BOTO_GET_METADATA_INSTANCE)

try:
  region = boto.utils.get_instance_metadata(timeout=timeout, num_retries=retries)['placement']['availability-zone'][:-1]
except:
  die(EXIT_BOTO_GET_METADATA_AZ)

try:
  conn = boto.ec2.connect_to_region(region)
except:
  die(EXIT_BOTO_CONNECT_REGION_FAIL)

try:
  reservations = conn.get_all_instances(instance_ids=[instance_id])
except:
  die(EXIT_BOTO_GET_ALL_INSTANCES_FAIL)

instance = reservations[0].instances[0]

try:
  caller = salt.client.Caller()
except:
  die(EXIT_SALT_CLIENT_FAIL)

for key, value in instance.tags.iteritems():
  key = str(key).translate(string.maketrans(":","_"))
  print("Tag " + key + " has a value of: " + value)
  try:
    caller.function('grains.setval', key, value)
  except:
    die(EXIT_SALT_GRAINS_SETVAL_FAIL)

die(EXIT_ALL_OK)
