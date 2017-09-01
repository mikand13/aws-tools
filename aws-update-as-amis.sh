#!/bin/bash -xl
cd aws-update-all-ecs-auto-scaling-groups
bundle install --path ~/.gem
bundle exec update-auto-scaling-groups.rb