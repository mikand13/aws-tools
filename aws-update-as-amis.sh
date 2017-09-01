#!/bin/bash -xl
cd aws-update-all-ecs-auto-scaling-groups
bundle install
ruby update-auto-scaling-groups.rb