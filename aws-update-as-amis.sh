#!/bin/bash -xl
cd aws-update-all-ecs-auto-scaling-groups
bundle install --path ~/.gem
bundle exec ruby update-auto-scaling-groups.rb
