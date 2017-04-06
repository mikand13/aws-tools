#!/bin/bash -xl
cd aws-ecr-cleaner
gem install aws-sdk
ruby clean-ecs.rb 7