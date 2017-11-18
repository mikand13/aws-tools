require 'aws-sdk'

def get_newest_image(region:)
  ec2_client = Aws::EC2::Client.new(region: region)

  images_result = ec2_client.describe_images({
                                                 filters: [
                                                     {
                                                         name:'name',
                                                         values: ['amzn-ami-*-amazon-ecs-optimized'],
                                                     },
                                                 ],
                                                 owners: ['amazon'],
                                                 dry_run: false,
                                             })

  images = images_result.images.sort_by { |x| Time.parse(x.creation_date) }.reverse
  newest_ami = images[0].image_id

  puts "New ECS AMI is: #{newest_ami}"

  newest_ami
end
