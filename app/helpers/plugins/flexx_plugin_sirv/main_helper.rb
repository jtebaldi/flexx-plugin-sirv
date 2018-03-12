module Plugins::FlexxPluginSirv::MainHelper
  def self.included(klass)
    # klass.helper_method [:my_helper_method] rescue "" # here your methods accessible from views
  end

  def flexx_plugin_sirv_on_active(plugin)
    if plugin.site.get_option("flexx_sirv_folder").blank?
      base_folder = "#{Digest::MD5.hexdigest(plugin.site.slug)}#{SecureRandom.hex(5)}"

      plugin.site.set_option("flexx_sirv_folder", base_folder)

      aws_settings = {
        access_key: @current_site.get_option("filesystem_s3_access_key"),
        secret_key: @current_site.get_option("filesystem_s3_secret_key"),
        bucket: @current_site.get_option("filesystem_s3_bucket_name")
      }

      fls = FlexxSirvUploader.new({current_site: plugin.site, thumb: nil, aws_settings: aws_settings}, self)
    end

    plugin
  end

  def flexx_plugin_sirv_on_inactive(plugin)
    plugin.site.set_option("flexx_sirv_folder", nil)
  end

  def flexx_plugin_sirv_on_upgrade(plugin)
  end

  def flexx_plugin_sirv_on_plugin_options(args)
    args[:links] << link_to('Settings', admin_plugins_flexx_plugin_sirv_settings_path)
  end

  def flexx_plugin_sirv_on_uploader(args)
    args[:custom_uploader] = FlexxSirvUploader.new({current_site: args[:current_site], thumb: args[:thumb], aws_settings: args[:aws_settings]}, self)
  end

  def flexx_plugin_sirv_before_upload(args)
    args[:generate_thumb] = false # we dont generate thumbs manually on Sirv
  end
end
