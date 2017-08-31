require './get-newest-ecs-optimized-ami'
require 'aws-sdk'
require 'securerandom'
require 'concurrent'

module NannoqTools
  class AutoScalingAMICycling
    attr_accessor :region

    def initialize(options)
      return nil unless options.class == Hash

      @region = options[:region]
    end

    def cycle_servers
      thread_pool = Concurrent::ThreadPoolExecutor.new(max_threads: 25)

      auto_scaling_client = Aws::AutoScaling::Client.new(region: @region)

      auto_scaling_client.describe_auto_scaling_groups.auto_scaling_groups.each do |group|
        thread_pool.post do
          as_name = group.auto_scaling_group_name

          as_mins = group.min_size
          as_maxs = group.max_size
          as_dc = group.desired_capacity
          launch_config_name = group.launch_configuration_name

          printf "Name is: #{as_name}\n"
          printf "Min Size is: #{as_mins}\n"
          printf "Max Size is: #{as_maxs}\n"
          printf "Desired Size is: #{as_dc}\n"
          printf "Launch Config Name is: #{launch_config_name}\n"

          search_param = {launch_configuration_names: [launch_config_name]}
          old_launch_config = auto_scaling_client.describe_launch_configurations(search_param).data
                                  .launch_configurations.first
          ami = old_launch_config.image_id
          instance_type = old_launch_config.instance_type
          user_data = old_launch_config.user_data

          new_ami = get_newest_image

          #if ami != new_ami
            printf "Old AMI is: #{ami}\n"
            printf "Old Instance Type is: #{instance_type}\n"
            printf "Old Launch Config User data is: #{user_data}\n"

            printf "New AMI is: #{new_ami}\n"

            printf "Creating new launch configuration for: #{as_name}\n"

            new_config = new_launch_config(old_config: old_launch_config, new_ami: new_ami)
            new_launch_configuration_name = new_config[:launch_configuration_name]

            printf "New Launch Configuration is: #{new_launch_configuration_name}\n"

            auto_scaling_client.create_launch_configuration(new_config)

            printf "Updating #{as_name} with new launch config #{new_launch_configuration_name}!\n"

            begin
              auto_scaling_client.update_auto_scaling_group({
                  auto_scaling_group_name: as_name,
                  launch_configuration_name: new_launch_configuration_name
              })

              printf "Set configuration on #{as_name} with new launch config #{new_launch_configuration_name}!\n"

              if group.instances.count > 0
                if cycle_auto_scaling_group(client: auto_scaling_client,
                                            group: get_group(client: auto_scaling_client, name: as_name),
                                            old_lc_name: launch_config_name,
                                            new_lc_name: new_launch_configuration_name)
                  printf "Update Complete for #{as_name}!\n\n"
                else
                  printf "Cycling failed for #{as_name}!\n\n"
                end
              else
                printf "Deleting old launch configuration: #{launch_config_name}\n"

                auto_scaling_client.delete_launch_configuration({launch_configuration_name: launch_config_name})

                printf "#{as_name} has no instances, update complete!\n"
              end
            rescue  Exception => e
              printf "#{e.message}\n"
              printf "#{e.backtrace.inspect}\n"

              printf "Error encountered in #{as_name} when setting new launch configuration, deleting and resetting group!\n"

              client.delete_launch_configuration({launch_configuration_name: new_launch_configuration_name})
              client.update_auto_scaling_group({
                 auto_scaling_group_name: as_name,
                 launch_configuration_name: launch_config_name,
                 min_size: as_mins,
                 max_size: as_maxs,
                 desired_capacity: as_dc
              })

              printf "Set reset on #{as_name}, terminating...\n"

              verify_healthy_and_count(client: client, name: as_name, count: as_dc)

              printf "Resuming scaling operations on #{name}\n"

              client.resume_processes({
                  auto_scaling_group_name: as_name,
                  scaling_processes: %w(ReplaceUnhealthy AZRebalance AlarmNotification ScheduledActions)
              })

              printf "Deleting new launch configuration: #{new_launch_configuration_name}\n"
            end
          #else
          #printf "Old AMI (#{ami}) does not differ from new AMI (#{new_ami})!"
          #end
        end
      end

      thread_pool.shutdown
      thread_pool.wait_for_termination

      printf "Completed cycling of all auto-scaling-groups...\n"
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
          instance_monitoring: old_config.instance_monitoring,
          spot_price: old_config.spot_price,
          iam_instance_profile: old_config.iam_instance_profile,
          ebs_optimized: old_config.ebs_optimized,
          associate_public_ip_address: old_config.associate_public_ip_address,
          placement_tenancy: old_config.placement_tenancy,
      }
    end

    def cycle_auto_scaling_group(client:, group:, old_lc_name:, new_lc_name:)
      as_name = group.auto_scaling_group_name

      printf "Cycling: #{as_name}\n"

      current_max = group.max_size
      current_desired = group.desired_capacity
      current_default_cooldown = group.default_cooldown

      begin
        new_size = current_desired * 2
        increase_max = new_size > current_max

        printf "Suspending scaling processes in: #{as_name}!\n"

        client.suspend_processes({
            auto_scaling_group_name: as_name,
            scaling_processes: %w(ReplaceUnhealthy AZRebalance AlarmNotification ScheduledActions)
        })

        printf "Will temporarily increase group to size: #{new_size} for blue/green deployment...\n"

        client.update_auto_scaling_group({
            auto_scaling_group_name: as_name,
            default_cooldown: 6000,
            desired_capacity: 4,
            max_size: increase_max ? new_size : group.max_size
        })

        printf "Set scaling on #{as_name}!\n"

        if scale_up_group(client: client, group: group, new_size: new_size)
          printf "#{as_name} is healthy and ready for cycling!\n"

          unless drain_and_kill_old_instances(client: client, group: group)
            decrement_group_sequentially(client: client, group: group, new_size: new_size, desired: current_desired, max: current_max)
          end
        end

        printf "Deleting old launch configuration: #{old_lc_name}\n"

        client.delete_launch_configuration({launch_configuration_name: old_lc_name})

        printf "Resetting old values on scaling group: #{as_name}\n"

        reset_scaling_group(client: client, name: as_name, orig_max: current_max, orig_desired: current_desired, orig_cooldown: current_default_cooldown)

        printf "Auto-Scaling group #{as_name} is healthy!\n"

        return true
      rescue  Exception => e
        printf "#{e.message}\n"
        printf "#{e.backtrace.inspect}\n"

        printf "Error encountered in #{as_name}, resetting...\n"

        client.delete_launch_configuration({launch_configuration_name: new_lc_name})

        printf "Deleting new launch configuration: #{new_lc_name}\n"

        reset_scaling_group(client: client, name: as_name, orig_max: current_max, orig_desired: current_desired, orig_cooldown: current_default_cooldown)

        printf "Auto-Scaling group #{as_name} is healthy!\n"

        return false
      end
    end

    def scale_up_group(client:, group:, new_size:)
      as_name = group.auto_scaling_group_name

      current_count = group.instances.count

      while current_count < new_size
        updated_group = get_group(client: client, name: as_name)
        current_count = updated_group.instances.count

        unless current_count >= new_size
          printf "Waiting for #{as_name} to scale up instances...\n"
          sleep(10)
        end
      end

      printf "Auto-Scaling group #{as_name} at correct count!\n"

      verify_healthy_and_count(client: client, name: as_name, count: new_size)
    end

    def drain_and_kill_old_instances(client:, group:)
      ecs_client = Aws::ECS::Client.new(region: @region)

      container_instance_arns = container_instances_for_group(group: group)

      container_instance_arns.each do |cluster_hash|
        ecs_client.update_container_instances_state({
            cluster: cluster_hash[:cluster],
            container_instances: cluster_hash[:arns],
            status: 'DRAINING'
        })
      end

      drained = false

      until drained
        updated_instances = container_instances(client: ecs_client, container_arns: container_instance_arns)
        drained = updated_instances.all? do |i|
          if i.running_tasks_count == 0 && i.lifecycle_state.eql?('InService')
            client.terminate_instance_in_auto_scaling_group({
                instance_id: i.ec2_instance_id,
                should_decrement_desired_capacity: true,
            })

            printf "Sleeping for 20 seconds to avoid unecessary scaling activity after shutting down a node in #{group.auto_scaling_group_name}\n"

            sleep(20)
          end

          i.running_tasks_count == 0
        end

        unless drained
          printf "Waiting for #{group.auto_scaling_group_name} to drain stale tasks...\n"
          sleep(10)
        end
      end

      drained
    end

    def container_instances(client:, container_arns:)
      container_instances = []

      container_arns.each do |cluster_hash|
        container_instances << client.describe_container_instances({
           cluster: cluster_hash[:cluster],
           container_instances: cluster_hash[:arns],
        }).container_instances
      end

      container_instances.flatten
    end

    def decrement_group_sequentially(client:, group:, scaled_size:, old_desired:, old_max:)
      as_name = group.auto_scaling_group_name
      current_desired = scaled_size

      until current_desired == old_desired
        client.update_auto_scaling_group({
           auto_scaling_group_name: as_name,
           desired_capacity: current_desired - 1
        })

        current_desired -= 1

        printf "Reduced #{as_name} with 1 instance, sleeping for 2 mins to allow for redeploy...\n"

        sleep(120)

        verify_healthy_and_count(client: client, name: as_name, count: current_desired)
      end

      printf "Cycled all instances for #{as_name}, setting old max!\n"

      client.update_auto_scaling_group({
         auto_scaling_group_name: as_name,
         max_size: old_max
      })
    end

    def verify_healthy_and_count(client:, name:, count:)
      all_instances_healthy = false

      until all_instances_healthy
        updated_group = get_group(client: client, name: name)
        all_instances_healthy = updated_group.instances.all? {
            |i| i.health_status.eql?('Healthy') && i.lifecycle_state.eql?('InService')
        } && updated_group.instances.count == count

        unless all_instances_healthy
          printf "Waiting for #{name} to only contain healthy instances...\n"
          sleep(10)
        end
      end

      all_instances_healthy
    end

    def reset_scaling_group(client:, name:, orig_max:, orig_desired:, orig_cooldown:)
      client.update_auto_scaling_group({
         auto_scaling_group_name: name,
         default_cooldown: orig_cooldown,
         desired_capacity: orig_desired,
         max_size: orig_max
      })

      printf "Set reset on #{name}\n"

      verify_healthy_and_count(client: client, name: name, count: orig_desired)

      printf "Resuming scaling operations on #{name}\n"

      client.resume_processes({
          auto_scaling_group_name: name,
          scaling_processes: %w(ReplaceUnhealthy AZRebalance AlarmNotification ScheduledActions)
      })
    end

    def get_group(client:, name:)
      client.describe_auto_scaling_groups(auto_scaling_group_names: [name]).data.auto_scaling_groups.first
    end

    def container_instances_for_group(group:)
      ecs_client = Aws::ECS::Client.new(region: @region)

      group_instance_ids = group.instances.map { |i| i.instance_id }
      instance_arns = []

      ecs_client.list_clusters.cluster_arns.each do |c|
        container_instances_arns = ecs_client.list_container_instances({cluster: c}).container_instance_arns

        if container_instances_arns.count > 0
          container_instances = ecs_client.describe_container_instances({cluster: c, container_instances: container_instances_arns}).container_instances

          arns = []

          container_instances.each do |instance|
            if group_instance_ids.any? { |s| s.include?(instance.ec2_instance_id) }
              arns << instance.container_instance_arn
            end
          end

          unless arns.empty?
            instance_arns << {cluster: c, arns: arns}
          end
        else
          printf "Cluster #{c} has no container instances!\n"
        end
      end

      printf "Cluster arns for #{group.auto_scaling_group_name} are #{instance_arns}\n"

      instance_arns
    end
  end
end

NannoqTools::AutoScalingAMICycling::new({region: 'eu-west-1'}).cycle_servers