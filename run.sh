#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <alarm_hour> <alarm_minute>"
  exit 1
fi

ALARM_HOUR=$1
ALARM_MINUTE=$2

processing-java --sketch=`pwd` --run --args $ALARM_HOUR $ALARM_MINUTE
