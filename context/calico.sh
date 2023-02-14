#!/usr/bin/env bash

kubectl apply -f applications/tigera-operator.yaml
kubectl apply -f applications/custom-resources.yaml