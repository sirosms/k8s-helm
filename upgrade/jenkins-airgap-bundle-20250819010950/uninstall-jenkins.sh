#!/bin/bash
helm list -n devops
helm uninstall -n devops jenkins
