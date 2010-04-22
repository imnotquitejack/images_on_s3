require 'RMagick'

class Magick::Image
  # image.auto_orient! # Rotates the image according to EXIF orientation tag
  # The above is broken in older versions of imagemagick (regardless of rmagick version)
  def reorient!
    self.get_exif_by_entry('Orientation')
    case self['EXIF:Orientation']
    when Magick::LeftBottomOrientation.to_i.to_s
      self.rotate!(-90)      
      self['EXIF:Orientation'] = Magick::TopLeftOrientation.to_i.to_s
    when Magick::RightTopOrientation.to_i.to_s
      self.rotate!(90)      
      self['EXIF:Orientation'] = Magick::TopLeftOrientation.to_i.to_s
    end
  end
end

module ImagesOnS3

  def has_images_on_s3( options = {} )
    attr_accessor :temp_data
    mattr_accessor :resize_options
    mattr_accessor :keep_original

    validates_uniqueness_of :filename, :allow_nil => true
    validates_inclusion_of :content_type, :in => %w( image/jpeg image/pjpeg image/gif image/png image/x-png image/jpg image/tiff ), :allow_nil => true
    
    if column_names.include?('size')
      validates_numericality_of :size
      validates_inclusion_of :size, :in => (1.kilobyte..10.megabytes)
    end
  
    before_validation :set_properties_from_image_data, :unless => Proc.new{|i| i.temp_data.blank? }
    after_validation :store_on_s3
    after_destroy :delete_from_s3
    
    include InstanceMethods unless included_modules.include?(InstanceMethods)
    
    self.resize_options = {}.update(options[:sizes])
    self.keep_original = (options.has_key?(:keep_original) ? options[:keep_original] : true)
  end
  
  module InstanceMethods
    def uploaded_data=(file_data)
      return nil if file_data.nil? || file_data.size == 0
      if file_data.is_a?(StringIO)
        file_data.rewind
      end
      self.temp_data = file_data.read
    end
  
    # If no size is given, then return the path to the original file.
    def path( size='' )
      return path(:original) if size.blank? || size.to_s == 'default'
      "#{self.class.table_name}/"+self.filename.gsub('.',"_#{size.to_s}.")
    end
    
    def public_url( size='' )
      "http://s3.amazonaws.com/#{SimpleS3.bucket_name}/#{path(size)}".untaint
    end
    
    protected
    
    def set_properties_from_image_data
      begin
        image = Magick::Image.from_blob( self.temp_data )[0]
        image.reorient!
        
        self.size = self.temp_data.length if self.has_attribute? :size
        self.content_type = determine_content_type_from_format( image.format )
        self.width = image.columns if self.has_attribute? :width
        self.height = image.rows if self.has_attribute? :height

        # Set filename / path
        string = Array.new(16) { rand(256) }.pack('C*').unpack('H*').first # RANDOM STRING
        self.filename = "#{string.at(0)}/#{string.at(1)}/#{string}.#{self.extension}"
      rescue => error
        logger.info "RMagick can't process data: #{error}"
        self.errors.add_to_base('Not a valid image')
      end
    end
    
    def store_on_s3
      logger.info "This object is: #{self.errors.empty? ? 'Valid' : 'Invalid'}"
      logger.info "#{self.errors.full_messages}" unless self.errors.empty?
      return unless self.errors.empty?
      
      # Don't save it to S3 if there's no file.
      return if self.temp_data.nil?
      
      # Saves the original
      if self.keep_original
        SimpleS3.save( self.path('original'), self.temp_data )
        logger.info "Saving #{self.path('original')} to S3..."
      end
      
      resize_options.each do |name, geometry|
        image = Magick::Image.from_blob( temp_data )[0]
        image.reorient!
        
        if image.rows > image.columns # It's a portrait, not a landscape
          geometry = geometry.split('x').reverse.join('x').tr('>','')+'>'
        end
        
        # Resize the original image data and save it.
        image.change_geometry!(geometry){ |cols, rows, img| img.resize!(cols,rows)}
        SimpleS3.save( self.path(name), image.to_blob { self.quality = 65 } )
        logger.info "Saving #{self.path(name)} to S3..."
      end
      
      self.temp_data = nil
    end
    
    def delete_from_s3
      return if self.filename.blank?
      
      if self.keep_original
        SimpleS3.delete( self.path('original') )
        logger.info "Deleting #{self.path('original')} from S3..."
      end
      
      resize_options.each do |name, geometry|
        SimpleS3.delete( self.path(name) )
        logger.info "Deleting #{self.path(name)} from S3..."
      end
    end
    
    def determine_content_type_from_format( format )
      case format
        when 'JPEG' then 'image/jpeg'
        when 'JPG' then 'image/jpeg'
        when 'GIF' then 'image/gif'
        when 'PNG' then 'image/png'
        else "unknown (#{format})"
      end
    end
    
    def extension
      case self.content_type
        when 'image/jpeg' then 'jpg'
        when 'image/jpg' then 'jpg'
        when 'image/pjpeg' then 'jpg'
        when 'image/png' then 'png'
        when 'image/x-png' then 'png'
        when 'image/gif' then 'gif'
        when 'image/tiff' then 'tiff'
        else "unknown_#{self.content_type.gsub('/','-')}"
      end
    end    
  end
  
end
