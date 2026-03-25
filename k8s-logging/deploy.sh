#!/bin/bash

sops --decrypt .env > .env.temp

set -a
source .env.temp
set +a

envsubst < base/config/fluent.conf.template > base/config/fluent.conf

kubectl apply -k overlays/cloud