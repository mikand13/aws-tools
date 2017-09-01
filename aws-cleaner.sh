#!/bin/bash -xl
cd aws-ecr-cleaner
bundle install --path ~/.gem
ruby clean-ecs.rb 7