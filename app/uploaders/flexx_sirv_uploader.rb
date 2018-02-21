class FlexxSirvUploader < CamaleonCmsUploader

  def after_initialize
    @cloudfront = @aws_settings[:cloud_front] || @current_site.get_option("filesystem_s3_cloudfront")
    @aws_region = @aws_settings[:region] || @current_site.get_option("filesystem_region", 'us-west-2')
    @aws_akey = @aws_settings[:access_key] || @current_site.get_option("filesystem_s3_access_key")
    @aws_asecret = @aws_settings[:secret_key] || @current_site.get_option("filesystem_s3_secret_key")
    @aws_bucket = @aws_settings[:bucket] || @current_site.get_option("filesystem_s3_bucket_name")
    @aws_settings[:aws_file_upload_settings] ||= lambda{|settings| settings }
    @aws_settings[:aws_file_read_settings] ||= lambda{|data, s3_file| data }
  end

  def browser_files(prefix = "", result = {})
    result["/#{prefix[0..-2]}"] = {files: {}, folders: {}}

    object_list = s3_client.list_objects(bucket: @aws_bucket, prefix: prefix)

    object_list.contents.each do |file|
      cache_item(
        {
          name: File.basename(file.key),
          key: "/#{file.key}",
          url: "https://tonanimm.sirv.com/#{file.key}",
          is_folder: false,
          size: file.size.round(2),
          format: self.class.get_file_format(file.key),
          type: (MIME::Types.type_for(file.key).first.content_type rescue ""),
          created_at: file.last_modified,
          thumb: "https://tonanimm.sirv.com/#{file.key}?profile=Thumb"
        }.with_indifferent_access,
        result
      ) if file.size > 0
    end

    object_list.common_prefixes.each do |folder|
      cache_item(
        {
          name: "#{folder.prefix[0..-2]}".gsub(prefix, ""),
          key: "/#{folder.prefix[0..-2]}",
          url: "",
          is_folder: true,
          size: 0,
          format: "folder",
          type: "",
          created_at: "",
          thumb: ""
        }.with_indifferent_access,
        result
      )

      browser_files("#{folder.prefix}", result)
    end

    @current_site.set_meta(cache_key, result) if prefix == ""

    result
  end

  def objects(prefix = '/', sort = 'created_at')
    if @aws_settings["inner_folder"].present?
      prefix = "#{@aws_settings["inner_folder"]}/#{prefix}".gsub('//', '/')
      prefix = prefix[0..-2] if prefix.end_with?('/')
    end
    super(prefix, sort)
  end

  # parse an AWS file into custom file_object
  def file_parse(s3_file)
    key = s3_file.is_a?(String) ? s3_file : s3_file.key
    is_dir = s3_file.is_a?(String) || File.extname(key) == ''

    {
        name: File.basename(key),
        key: "/#{key}",
        url: is_dir ? '' : "https://tonanimm.sirv.com/#{key}",
        is_folder: is_dir,
        size: is_dir ? 0 : s3_file.size.round(2),
        format: is_dir ? 'folder' : self.class.get_file_format(key),
        deleteUrl: '',
        thumb: "https://tonanimm.sirv.com/#{key}?profile=Thumb",
        type: is_dir ? '' : (MIME::Types.type_for(key).first.content_type rescue ""),
        created_at: is_dir ? '' : s3_file.last_modified,
        dimension: ''
    }.with_indifferent_access
  end

  def add_file(uploaded_io_or_file_path, key, args = {})
    return if args[:is_thumb] # we dont generate thumbs manually on Sirv

    args, res = {same_name: false, is_thumb: false}.merge(args), nil
    key = "#{@aws_settings["inner_folder"]}/#{key}" if @aws_settings["inner_folder"].present?
    key = search_new_key(key) unless args[:same_name]

    s3_file = bucket.object(key.split('/').clean_empty.join('/'))
    s3_file.upload_file(uploaded_io_or_file_path.is_a?(String) ? uploaded_io_or_file_path : uploaded_io_or_file_path.path, @aws_settings[:aws_file_upload_settings].call({acl: 'public-read'}))
    res = cache_item(file_parse(s3_file))
    res
  end

  # add new folder to AWS with :key
  def add_folder(key)
    key = "#{@aws_settings["inner_folder"]}/#{key}" if @aws_settings["inner_folder"].present?
    s3_file = bucket.object(key.split('/').clean_empty.join('/') << '/')
    s3_file.put(body: nil)
    cache_item(file_parse(s3_file))
    s3_file
  end

  def delete_folder(key)
    folder_name = key.split('/').clean_empty.join('/')

    bucket.objects(bucket: @aws_bucket, prefix: folder_name).batch_delete!

    begin
      s3_client.list_objects(bucket: @aws_bucket, prefix: folder_name).common_prefixes.each do |folder|
        delete_folder(folder.prefix)
      end

      bucket.object("#{folder_name}/").delete
    rescue Aws::S3::Errors::NotFound
    end
  end

  # delete a file in AWS with :key
  def delete_file(key)
    key = "#{@aws_settings["inner_folder"]}/#{key}" if @aws_settings["inner_folder"].present?
    bucket.object(key.split('/').clean_empty.join('/')).delete rescue ''
    @instance.hooks_run('after_delete', key)

    reload
  end

  # initialize a bucket with AWS configurations
  # return: (AWS Bucket object)
  def bucket
    @bucket ||=Aws::S3::Resource.new(
      endpoint: 'https://s3.sirv.com',
      region: 'us-east-1',
      force_path_style: true,
      signature_version: 's3',
      credentials: Aws::Credentials.new(@aws_akey, @aws_asecret)
      ).bucket(@aws_bucket)
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new(
      endpoint: 'https://s3.sirv.com',
      region: 'us-east-1',
      force_path_style: true,
      signature_version: 's3',
      credentials: Aws::Credentials.new(@aws_akey, @aws_asecret)
      )
  end
end
