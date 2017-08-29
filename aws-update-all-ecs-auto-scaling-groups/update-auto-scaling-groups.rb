require './get-newest-ecs-optimized-ami'
require 'aws-sdk'
require 'securerandom'
require 'concurrent'

def cycle_servers
  thread_pool = Concurrent::ThreadPoolExecutor.new(max_threads: 25)

  auto_scaling_client = Aws::AutoScaling::Client.new(region: 'eu-west-1')

  auto_scaling_client.describe_auto_scaling_groups.auto_scaling_groups.each do |group|
    thread_pool.post do
      as_name = group.auto_scaling_group_name

      if group.instances.count > 0
        puts 'Found non-empty Auto-Scaling Group!'

        as_mins = group.min_size
        as_maxs = group.max_size
        as_dc = group.desired_capacity
        launch_config_name = group.launch_configuration_name

        puts "Name is: #{as_name}"
        puts "Min Size is: #{as_mins}"
        puts "Max Size is: #{as_maxs}"
        puts "Desired Size is: #{as_dc}"
        puts "Launch Config Name is: #{launch_config_name}"

        search_param = {launch_configuration_names: [launch_config_name]}
        old_launch_config = auto_scaling_client.describe_launch_configurations(search_param).data
                                .launch_configurations.first
        ami = old_launch_config.image_id
        instance_type = old_launch_config.instance_type
        user_data = old_launch_config.user_data

        new_ami = get_newest_image

        #if ami != new_ami
          puts "Old AMI is: #{ami}"
          puts "Old Instance Type is: #{instance_type}"
          puts "Old Launch Config User data is: #{user_data}"

          puts "New AMI is: #{new_ami}"

          puts "Creating new launch configuration for: #{as_name}"

          new_config = new_launch_config(old_config: old_launch_config, new_ami: new_ami)
          new_launch_configuration_name = new_config[:launch_configuration_name]

          puts "New Launch Configuration is: #{new_launch_configuration_name}"

          auto_scaling_client.create_launch_configuration(new_config)

          puts "Updating #{as_name} with new launch config #{new_launch_configuration_name}!"

          auto_scaling_client.update_auto_scaling_group({
              auto_scaling_group_name: as_name,
              launch_configuration_name: new_launch_configuration_name
          })

          puts "Deleting old launch configuration: #{launch_config_name}"

          auto_scaling_client.delete_launch_configuration({launch_configuration_name: launch_config_name})

          if as_name.include?('auxiliary')
              cycle_auto_scaling_group(client: auto_scaling_client, group: group)

              puts "Update Complete for #{as_name}!"
              puts
          end
        #else
          #puts "Old AMI (#{ami}) does not differ from new AMI (#{new_ami})!"
        #end
      else
        puts "Auto-Scaling Group: #{as_name} is empty!"
      end
    end
  end

  thread_pool.shutdown
  thread_pool.wait_for_termination

  puts 'Completed cycling of all auto-scaling-groups...'
end

def new_launch_config(old_config:, new_ami:)
  if old_config.launch_configuration_name.start_with?('GENERATED')
    new_name = "#{old_config.launch_configuration_name.split('====').first}====#{SecureRandom::uuid}"
  else
    new_name = "GENERATED_#{old_config.launch_configuration_name}====#{SecureRandom::uuid}"
  end

  {
    launch_configuration_name: new_name,
    image_id: new_ami,
    key_name: old_config.key_name,
    security_groups: old_config.security_groups,
    user_data: old_config.user_data,
    instance_type: old_config.instance_type,
    block_device_mappings: old_config.block_device_mappings,
    instance_monitoring: old_config.instance_monitoring,
    spot_price: old_config.spot_price,
    iam_instance_profile: old_config.iam_instance_profile,
    ebs_optimized: old_config.ebs_optimized,
    associate_public_ip_address: old_config.associate_public_ip_address,
    placement_tenancy: old_config.placement_tenancy,
  }
end

def cycle_auto_scaling_group(client:, group:)
  as_name = group.auto_scaling_group_name

  puts "Cycling: #{}"

  current_max = group.max_size
  current_desired = group.desired_capacity
  current_default_cooldown = group.default_cooldown
  
  new_size = current_desired * 2
  increase_max = new_size > current_max

  puts "Will temporarily increase group to size: #{new_size} for blue/green deployment..."

  group.update({default_cooldown: 6000, desired_capacity: 4, max_size: increase_max ? new_size : group.max_size})

  current_count = group.auto_scaling_instances.count

  while current_count < new_size
    current_count = get_group(client: client, name: as_name).auto_scaling_instances.count

    unless current_count >= new_size
      puts "Waiting for #{as_name} to scale up instances..."
      sleep(10)
    end
  end

  puts "Auto-Scaling group #{as_name} at correct count!"

  all_instances_healthy = false

  until all_instances_healthy
    all_instances_healthy = get_group(client: client, name: as_name).auto_scaling_instances.all? { |i| i.health_status.eql? 'Healthy' }

    unless all_instances_healthy
      puts "Waiting for #{as_name} to only contain healthy instances..."
      sleep(10)
    end
  end

  puts "Auto-Scaling group #{as_name} is healthy!"
end

def get_group(client:, name:)
  client.describe_auto_scaling_groups(auto_scaling_group_names: name).data.auto_scaling_groups.first
end

cycle_servers