#!/bin/bash -xl
cd aws-ecr-cleaner
bundle install --path ~/.gem
bundle exec clean-ecs.rb 7