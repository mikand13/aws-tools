#!/bin/bash -xl
cd aws-ecr-cleaner
bundle install
ruby clean-ecs.rb 7