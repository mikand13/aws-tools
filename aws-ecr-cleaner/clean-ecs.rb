require 'aws-sdk'
require 'date'

days = ARGV[0]
default_days = 7

ecr = Aws::ECR::Client.new(region: 'eu-west-1')

ecr.describe_repositories.repositories.each do |repo|
  puts "Deleting images for #{repo.repository_name}..."

  images_to_delete = {}
  images_to_describe = []

  ecr.list_images(repository_name: repo.repository_name).each do |image|
    image.image_ids.each do |id|
      if id.image_tag != 'latest'
        images_to_delete[id.image_digest] = id
        images_to_describe << id
      end
    end

    puts "Images to delete: #{images_to_delete}"

    if images_to_delete.count > 0
      details = ecr.describe_images(repository_name: repo.repository_name, image_ids: images_to_describe).image_details

      details.each do |detail|
        puts detail.image_pushed_at

        if detail.image_pushed_at.to_time.to_date > Date.today - days.to_i ||= default_days
          puts "Purged non outdated images: #{detail.image_digest}"

          images_to_delete.delete(detail.image_digest)
        end
      end

      if images_to_delete.count > 0
        puts "Deleting #{images_to_delete.count} images for: #{repo.repository_name}"

        ecr.batch_delete_image(registry_id: repo.registry_id, repository_name: repo.repository_name, image_ids: images_to_delete.values)
      elsif
        puts "Skipping image with no outdated removables..."
      end
    elsif
      puts "Skipping image with no valid removables..."
    end

    images_to_delete = []
  end

  puts "Deletion complete for #{repo.repository_name}..."
end

