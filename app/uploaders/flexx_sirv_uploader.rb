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

  # recover all files from AWS and parse it to save into DB as cache
  def browser_files_old
    objects = {}
    objects['/'] = {files: {}, folders: {}}
    bucket.objects(@aws_settings["inner_folder"].present? ? {prefix: @aws_settings["inner_folder"]} : nil).each do |file|
      cache_item(file_parse(file), objects)
    end
    @current_site.set_meta(cache_key, objects)
    objects
  end

  def browser_files(prefix: '/')
    folder = {}.tap {|folder| folder[prefix] = {files: {}, folders: {}}}

    {}.tap do |result|
      object_list = s3_client.list_objects(bucket: @aws_bucket, prefix: prefix)
      object_list.contents.each do |file|
        cache_item(
          {
            name: File.basename(file.key),
            key: "/#{file.key}",
            url: "https://tonanimm.sirv.com/#{file.key}",
            is_folder: false,
            size: file.size,
            format: self.class.get_file_format(file.key),
            type: (MIME::Types.type_for(file.key).first.content_type rescue ""),
            created_at: file.last_modified,
            thumb: "https://tonanimm.sirv.com/#{file.key}?profile=Thumb"
          }.with_indifferent_access,
          folder
        ) if file.size > 0
      end
    end

    @current_site.set_meta(cache_key, folder)

    folder
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
    key = "/#{key}" unless key.starts_with?('/')
    is_dir = s3_file.is_a?(String) || File.extname(key) == ''
    res = {
        "name" => File.basename(key),
        "key" => key,
        "url" => is_dir ? '' : (@cloudfront.present? ? File.join(@cloudfront, key) : s3_file.public_url),
        "is_folder" => is_dir,
        "size" => is_dir ? 0 : s3_file.size.round(2),
        "format" => is_dir ? 'folder' : self.class.get_file_format(key),
        "deleteUrl" => '',
        "thumb" => '',
        'type' => is_dir ? '' : (s3_file.content_type rescue (MIME::Types.type_for(key).first.content_type rescue "")),
        'created_at' => is_dir ? '' : s3_file.last_modified,
        'dimension' => ''
    }.with_indifferent_access
    res["thumb"] = version_path(res['url']) if res['format'] == 'image' && File.extname(res['name']).downcase != '.gif'
    # if res['format'] == 'image' # TODO: Recover image dimension (suggestion: save dimesion as metadata)
    @aws_settings[:aws_file_read_settings].call(res, s3_file)
  end

  # add a file object or file path into AWS server
  # :key => (String) key of the file ot save in AWS
  # :args => (HASH) {same_name: false, is_thumb: false}, where:
  #   - same_name: false => avoid to overwrite an existent file with same key and search for an available key
  #   - is_thumb: true => if this file is a thumbnail of an uploaded file
  def add_file(uploaded_io_or_file_path, key, args = {})
    args, res = {same_name: false, is_thumb: false}.merge(args), nil
    key = "#{@aws_settings["inner_folder"]}/#{key}" if @aws_settings["inner_folder"].present? && !args[:is_thumb]
    key = search_new_key(key) unless args[:same_name]

    if @instance # private hook to upload files by different way, add file data into result_data
      _args={result_data: nil, file: uploaded_io_or_file_path, key: key, args: args, klass: self}; @instance.hooks_run('uploader_aws_before_upload', _args)
      return _args[:result_data] if _args[:result_data].present?
    end

    s3_file = bucket.object(key.split('/').clean_empty.join('/'))
    s3_file.upload_file(uploaded_io_or_file_path.is_a?(String) ? uploaded_io_or_file_path : uploaded_io_or_file_path.path, @aws_settings[:aws_file_upload_settings].call({acl: 'public-read'}))
    res = cache_item(file_parse(s3_file)) unless args[:is_thumb]
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

  # delete a folder in AWS with :key
  def delete_folder(key)
    key = "#{@aws_settings["inner_folder"]}/#{key}" if @aws_settings["inner_folder"].present?
    bucket.objects(prefix: key.split('/').clean_empty.join('/') << '/').delete
    reload
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
    @bucket ||= lambda{
      s3 = Aws::S3::Resource.new(endpoint: 'https://s3.sirv.com', region: 'us-east-1', force_path_style: true, signature_version: 'v4', credentials: Aws::Credentials.new(@aws_akey, @aws_asecret))
      bucket = s3.bucket(@aws_bucket)
    }.call
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new(endpoint: 'https://s3.sirv.com', region: 'us-east-1', force_path_style: true, signature_version: 'v4', credentials: Aws::Credentials.new(@aws_akey, @aws_asecret))
  end
end