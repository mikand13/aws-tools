# aws-tools
Simple tools for doing tasks on AWS.

## AWS ECS Registry Cleaner

This is a tool for deleting old images from the ECS Container Registry (ECR). It accepts a parameter of days to prevent deleting the newest images. 7 is default. It has no filtere capacity and will delete everything older than the set amount of days calculated from the instant you run the script.

### Steps

1. cd aws-ecr-cleaner
2. bundle install
3. ruby clean-ecs.rb [dont delete newer than this number of days] (7 is default)

## AWS EC2 Auto-Scaling Group Updater

This is a tool for updating all autoscaling groups with the most current ECS Optimized AMI. It will scan all auto-scaling groups, create updated launch configurations, and replace all vms while ensuring that all vms are properly drained in ECS to ensure a blue/green deployment of the containers on the autoscaling group. It will then kill all old vms. It bases updates on updating the most current launch configuration, so you can still make changes and update autoscaling groups manually without impacting this script.

### Steps

1. cd aws-update-all-ecs-auto-scaling-groups
2. bundle install
3. ruby update-auto-scaling-groups.rb

## AWS S3 PNG to JPG Converter

Creates a jpg clone of all png files in an S3 bucket.

### Steps

1. cd png-to-jps-on-s3-converter
2. bundle install
3. ruby converter.rb
