#!/bin/bash
source .env
envsubst <base/config/fluent.conf.template >base/config/fluent.conf
kubectl apply -k overlays/default
