require 'aws-sdk'

s3 = Aws::S3::Client.new(region: 'eu-west-1')
bucket = Aws::S3::Bucket.new('nannoq', client: s3)

bucket.objects.each do |objectsummary|
  object = objectsummary.object
  object_key = object.key

  puts "Parsing key: #{object_key}"

  if object_key.end_with?('.png')
    puts "Found possible conversion target at: #{object_key}"

    jpg_key = "#{object_key.chomp('.png')}.jpg"

    jpgObject = Aws::S3::Object.new('nannoq', jpg_key)

    unless jpgObject.exists?
      puts "Copying from #{object_key} to #{jpg_key}!"

      object.copy_to(bucket: 'nannoq', key: jpg_key)

      puts "Success: #{jpgObject.exists?}"
    else
      puts "Convert already exists!"
    end
  end
end
