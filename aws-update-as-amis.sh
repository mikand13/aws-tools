#!/bin/bash -xl
cd aws-update-all-ecs-auto-scaling-groups
bundle install --path ~/.gem
ruby update-auto-scaling-groups.rb