require 'aws/s3'
module SimpleS3
  @@config = YAML.load(ERB.new(File.read((RAILS_ROOT + '/config/amazon_s3.yml'))).result)[RAILS_ENV].symbolize_keys
  @@connection = AWS::S3::Base.establish_connection!(
    :access_key_id     => @@config[:access_key_id],
    :secret_access_key => @@config[:secret_access_key]
    )
    
  def self.file_exists?(path)
    AWS::S3::S3Object.exists?( path, @@config[:bucket_name] )
  end
  
  def self.about( path )
    AWS::S3::S3Object.about( path, @@config[:bucket_name] )
  end
  
  def self.delete(path)
    AWS::S3::S3Object.delete(  path, @@config[:bucket_name] )
  end
  
  def self.save(path, data)
    AWS::S3::S3Object.store( path, data, @@config[:bucket_name], :access => :public_read, 'cache-control' => 'public', "expires" => (Time.now+20.years).httpdate )
  end
  
  def self.list( path = '')
    AWS::S3::Bucket.objects( @@config[:bucket_name] ).collect{|o| o.path.gsub("/#{self.bucket_name}",'')}.select{|o| o.match(/^\/#{path}\//)}
  end
  
  def self.bucket_name
    @@config[:bucket_name]
  end
  
end
