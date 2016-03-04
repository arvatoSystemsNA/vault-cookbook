#
# Cookbook: hashicorp-vault
# License: Apache 2.0
#
# Copyright 2015-2016, Bloomberg Finance L.P.
#
require 'poise'

module VaultCookbook
  module Resource
    # A `vault_config` resource for managing Vault's configuration
    # files.
    # @action create
    # @provides vault_config
    # @since 1.0
    class VaultConfig < Chef::Resource
      include Poise(fused: true)
      provides(:vault_config)
      default_action(:create)

      # @!attribute path
      # @return [String]
      attribute(:path, kind_of: String, name_attribute: true)

      # @!attribute owner
      # @return [String]
      attribute(:owner, kind_of: String, default: 'vault')

      # @!attribute group
      # @return [String]
      attribute(:group, kind_of: String, default: 'vault')

      # @see https://vaultproject.io/docs/config/index.html
      attribute(:address, kind_of: String)
      attribute(:tls_disable, equal_to: [true, false, 1, 0, 'yes', 'no'], default: true)
      attribute(:tls_cert_file, kind_of: String)
      attribute(:tls_key_file, kind_of: String)
      attribute(:bag_name, kind_of: String, default: 'secrets')
      attribute(:bag_item, kind_of: String, default: 'vault')
      attribute(:disable_mlock, equal_to: [true, false], default: false)
      attribute(:default_lease_ttl, kind_of: String)
      attribute(:max_lease_ttl, kind_of: String)
      attribute(:statsite_addr, kind_of: String)
      attribute(:statsd_addr, kind_of: String)
      attribute(:backend_type, default: 'inmem', equal_to: %w{consul etcd zookeeper dynamodb s3 mysql postgresql inmem file})
      attribute(:backend_options, option_collector: true)
      attribute(:habackend_type, kind_of: String)
      attribute(:habackend_options, option_collector: true)
      attribute(:manage_certificate, equal_to: [true, false], default: false)

      def tls?
        if tls_disable === true || tls_disable === 'yes' || tls_disable === 1
          false
        else
          true
        end
      end

      # Transforms the resource into a JSON format which matches the
      # Vault service's configuration format.
      # @see https://vaultproject.io/docs/config/index.html
      def to_json
        # top-level
        config_keeps = %i{disable_mlock default_lease_ttl max_lease_ttl}
        config = to_hash.keep_if do |k, _|
          config_keeps.include?(k.to_sym)
        end
        # listener
        listener_keeps = tls? ? %i{address tls_cert_file tls_key_file} : %i{address}
        listener_options = to_hash.keep_if do |k, _|
          listener_keeps.include?(k.to_sym)
        end.merge(tls_disable: tls_disable.to_s)
        config['listener'] = { 'tcp' => listener_options }
        # backend
        config['backend'] = { backend_type => (backend_options || {}) }
        # ha_backend, only some backends support HA
        if %w{consul etcd zookeeper dynamodb}.include? habackend_type
          config['ha_backend'] = { habackend_type => (habackend_options || {}) }
        end
        # telemetry
        telemetry_keeps = %i{statsite_addr statsd_addr}
        telemetry_options = to_hash.keep_if do |k, _|
          telemetry_keeps.include?(k.to_sym)
        end
        config['telemetry'] = telemetry_options unless telemetry_options.empty?

        JSON.pretty_generate(config, quirks_mode: true)
      end

      action(:create) do
        notifying_block do
          if new_resource.manage_certificate
            include_recipe 'chef-vault::default'

            [new_resource.tls_cert_file, new_resource.tls_key_file].each do |dirname|
              directory ::File.dirname(dirname) do
                recursive true
              end
            end

            item = chef_vault_item(new_resource.bag_name, new_resource.bag_item)
            file new_resource.tls_cert_file do
              content item['certificate']
              mode '0644'
              owner new_resource.owner
              group new_resource.group
            end

            file new_resource.tls_key_file do
              sensitive true
              content item['private_key']
              mode '0640'
              owner new_resource.owner
              group new_resource.group
            end
          end

          directory ::File.dirname(new_resource.path) do
            recursive true
          end

          file new_resource.path do
            content new_resource.to_json
            owner new_resource.owner
            group new_resource.group
            mode '0640'
          end
        end
      end

      action(:delete) do
        notifying_block do
          if new_resource.manage_certificate
            file new_resource.tls_cert_file do
              action :delete
            end

            file new_resource.tls_key_file do
              action :delete
            end
          end

          file new_resource.path do
            action :delete
          end
        end
      end
    end
  end
end
