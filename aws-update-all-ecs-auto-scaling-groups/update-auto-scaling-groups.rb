require '../aws-missing-tools/lib/aws-missing-tools/aws-ha-release'
require './get-newest-ecs-optimized-ami'
require 'aws-sdk'

ec2_client = Aws::EC2::Client.new(region: 'eu-west-1')
auto_scaling_client = Aws::AutoScaling::Client.new(region: 'eu-west-1')

ami = get_newest_image

auto_scaling_client.describe_auto_scaling_groups.auto_scaling_groups.each do |group|
  as_name = group.auto_scaling_group_name

  puts "Name is: #{as_name}"

  if group.instances.count > 0
    as_mins = group.min_size
    as_maxs = group.max_size
    as_dc = group.desired_capacity

    puts "Min Size is: #{as_mins}"
    puts "Max Size is: #{as_maxs}"
    puts "Desired Size is: #{as_dc}"

    instance_type = ec2_client.describe_instances({ instance_ids: [group.instances.first.instance_id] }).first
                        .reservations.first
                        .instances.first
                        .instance_type

    puts "Instance Type is: #{instance_type}", ''
  else
    puts "Auto-Scaling Group: #{as_name} is empty!"
  end
end