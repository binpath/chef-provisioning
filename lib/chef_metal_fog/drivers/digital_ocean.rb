require 'chef_metal_fog/fog_driver'

#   fog:DigitalOcean:<client id>
module ChefMetalFog
  module Drivers
    class DigitalOcean < ChefMetalFog::FogDriver

      def bootstrap_options_for(action_handler, machine_spec, machine_options)
        bootstrap_options = symbolize_keys(machine_options[:bootstrap_options] || {})
        unless bootstrap_options[:key_name]
          bootstrap_options[:key_name] = overwrite_default_key_willy_nilly(action_handler)
        end

        tags = {
          'Name' => machine_spec.name,
          'BootstrapId' => machine_spec.id,
          'BootstrapHost' => Socket.gethostname,
          'BootstrapUser' => Etc.getlogin
        }
        # User-defined tags override the ones we set
        tags.merge!(bootstrap_options[:tags]) if bootstrap_options[:tags]
        bootstrap_options.merge!({ :tags => tags })

        if !bootstrap_options[:image_id]
          bootstrap_options[:image_name] ||= 'CentOS 6.4 x32'
          bootstrap_options[:image_id] = compute.images.select { |image| image.name == bootstrap_options[:image_name] }.first.id
        end
        if !bootstrap_options[:flavor_id]
          bootstrap_options[:flavor_name] ||= '512MB'
          bootstrap_options[:flavor_id] = compute.flavors.select { |flavor| flavor.name == bootstrap_options[:flavor_name] }.first.id
        end
        if !bootstrap_options[:region_id]
          bootstrap_options[:region_name] ||= 'San Francisco 1'
          bootstrap_options[:region_id] = compute.regions.select { |region| region.name == bootstrap_options[:region_name] }.first.id
        end
        found_key = compute.ssh_keys.select { |k| k.name == bootstrap_options[:key_name] }.first
        if !found_key
          raise "Could not find key named '#{bootstrap_options[:key_name]}' on #{driver_url}"
        end
        bootstrap_options[:ssh_key_ids] ||= [ found_key.id ]

        # You don't get to specify name yourself
        bootstrap_options[:name] = machine_spec.name
        bootstrap_options[:name] ||= machine_spec.name

        bootstrap_options
      end

      def self.compute_options_for(provider, id, config)
        new_compute_options = {}
        new_compute_options[:provider] = provider
        new_config = { :driver_options => { :compute_options => new_compute_options }}
        new_defaults = {
          :driver_options => { :compute_options => {} },
          :machine_options => { :bootstrap_options => {} }
        }
        result = Cheffish::MergedConfig.new(new_config, config, new_defaults)

        new_compute_options[:digitalocean_client_id] = id if (id && id != '')

        # This uses ~/.tugboat, generated by "tugboat authorize" - see https://github.com/pearkes/tugboat
        tugboat_file = File.expand_path('~/.tugboat')
        if File.exist?(tugboat_file)
          tugboat_data = YAML.load(IO.read(tugboat_file))
          new_compute_options.merge!(
            :digitalocean_client_id => tugboat_data['authentication']['client_key'],
            :digitalocean_api_key => tugboat_data['authentication']['api_key']
          )
          new_defaults[:machine_options].merge!(
            #:ssh_username => tugboat_data['ssh']['ssh_user'],
            :ssh_options => {
              :port => tugboat_data['ssh']['ssh_port'],
              # TODO we ignore ssh_key_path in favor of ssh_key / key_name stuff
              #:key_data => [ IO.read(tugboat_data['ssh']['ssh_key_path']) ] # TODO use paths, not data?
            }
          )

          # TODO verify that the key_name exists and matches the ssh key path

          new_defaults[:machine_options][:bootstrap_options].merge!(
            :region_id => tugboat_data['defaults']['region'].to_i,
            :image_id => tugboat_data['defaults']['image'].to_i,
            :size_id => tugboat_data['defaults']['region'].to_i,
            :private_networking => tugboat_data['defaults']['private_networking'] == 'true',
            :backups_enabled => tugboat_data['defaults']['backups_enabled'] == 'true',
          )
          ssh_key = tugboat_data['defaults']['ssh_key']
          if ssh_key && ssh_key.size > 0
            new_defaults[:machine_options][:bootstrap_options][:key_name] = ssh_key
          end
        end
        id = result[:driver_options][:compute_options][:digitalocean_client_id]

        [result, id]
      end

    end
  end
end
