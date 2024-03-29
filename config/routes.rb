Rails.application.routes.draw do

    scope PluginRoutes.system_info["relative_url_root"] do
      scope '(:locale)', locale: /#{PluginRoutes.all_locales}/, :defaults => {  } do
        # frontend
        namespace :plugins do
          namespace 'flexx_plugin_sirv' do
            get 'index' => 'front#index'
          end
        end
      end

      #Admin Panel
      scope :admin, as: 'admin', path: PluginRoutes.system_info['admin_path_name'] do
        namespace 'plugins' do
          namespace 'flexx_plugin_sirv' do
            controller :admin do
              get :index
              get :settings
              post :save_settings
            end
          end
        end
      end

      # main routes
      #scope 'flexx_plugin_sirv', module: 'plugins/flexx_plugin_sirv/', as: 'flexx_plugin_sirv' do
      #  Here my routes for main routes
      #end
    end
  end
