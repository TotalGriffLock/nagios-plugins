#!/bin/bash
# Check you cant ping something
# 20220811  jg@cyberfit.uk  Initial version

HOST=$1

function check_ping {
  ping -c 1 -w 2 $HOST | grep '0 received' > /dev/null
}


if check_ping; then
  echo OK: Cant ping $HOST
  exit 0
else
  echo CRITICAL: Can ping $HOST - it should not be responding
  exit 2
fi
