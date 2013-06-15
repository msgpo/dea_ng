require "json"

require "dea/win_staging_task_workspace"

module Dea
  class WinStagingTask < StagingTask

    def workspace
      @workspace ||= WinStagingTaskWorkspace.new(config["base_dir"])
    end

    def promise_prepare_staging_log_script(warden_staged_dir, warden_staging_log)
      commands = [
        { :cmd => 'mkdir', :args => [ "#{warden_staged_dir}/logs" ] },
        { :cmd => 'touch', :args => [ warden_staging_log ] },
      ]
      commands.to_json
    end

    def promise_app_dir_script
      # NB: chown not necessary as /app will inherit perms
      commands = [
        { :cmd => 'mkdir', :args => [ '@ROOT@/app' ] },
        { :cmd => 'touch', :args => [ '@ROOT@/app/support_heroku_buildpacks' ] },
      ]
      commands.to_json
    end

    def promise_log_upload_finished_script(warden_staging_log)
      commands = [
        {
          :cmd => 'ps1',
          :args => [ %Q|Add-Content -Encoding ASCII -Path #{warden_staging_log} "----> Uploaded  droplet"| ]
        }
      ]
      commands.to_json
    end

    def promise_pack_buildpack_cache_script(warden_cache, warden_staged_buildpack_cache)
      commands = [
        { :cmd => 'mkdir', :args => [ warden_cache ] },
        { :cmd => 'tar', :args => [ warden_cache, warden_staged_buildpack_cache ] },
      ]
      commands.to_json
    end

    def promise_pack_app_script(warden_staged_dir, warden_staged_droplet)
      commands = [
        { :cmd => 'tar', :args => [ warden_staged_dir, warden_staged_droplet ] },
      ]
      commands.to_json
    end

    def promise_log_upload_started_script(warden_staged_droplet, warden_staging_log)
      commands = [
        { :cmd => 'ps1', :args => [
            %Q|$droplet_item_length = (Get-Item '#{warden_staged_droplet}').Length|,
            %q|$droplet_item_length_str = '{0:N0}KB' -f ($droplet_item_length / 1KB)|,
            %Q|Add-Content -Encoding ASCII -Path #{warden_staging_log} "----> Uploading staged droplet ($droplet_item_length_str)"| ]
        },
      ]
      commands.to_json
    end

    def promise_unpack_app_script(droplet_path, warden_staging_log, warden_unstaged_dir)
      commands = [
        { :cmd => 'ps1', :args => [
            %Q|$droplet_item_length = (Get-Item '#{droplet_path}').Length|,
            %q|$droplet_item_length_str = '{0:N0}KB' -f ($droplet_item_length / 1KB)|,
            %Q|Add-Content -Encoding ASCII -Path #{warden_staging_log} "----> Downloaded app package ($droplet_item_length_str)"| ]
        },
        { :cmd => 'unzip', :args => [ droplet_path, warden_unstaged_dir ] },
      ]
      commands.to_json
    end

    def promise_stage_script

      staging_config_path = ''
      if staging_config['environment'].has_key?('PATH')
        staging_config_path = staging_config['environment']['PATH'].gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
      else
        staging_config_path = File.dirname(config['dea_ruby']).gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
      end

      args = [ '# DEBUGGER' ]
      args << staging_environment
      args << %Q|$env:PATH="$env:PATH;#{staging_config_path}"|
      args << %Q|$env:CONTAINER_ROOT='@ROOT@'|
      args << %Q!#{config['dea_ruby']} '#{run_plugin_path}' '#{workspace.plugin_config_path}' 2>&1 | Out-File -Append -Encoding ASCII -FilePath '#{workspace.warden_staging_log}'!
      args.flatten!

      commands = [
        { :cmd => 'replace-tokens', :args => [ workspace.plugin_config_path ] }, # NB: technically we shouldn't be able to modify this file in-place.
        { :cmd => 'ps1', :args => args }
      ]

      commands.to_json
    end

    def staging_environment
      {
        "PLATFORM_CONFIG" => workspace.platform_config_path,
        "BUILDPACK_CACHE" => staging_config["environment"]["BUILDPACK_CACHE"],
        "STAGING_TIMEOUT" => staging_timeout
      }.map { |k, v| "$env:#{k}='#{v}'" }
    end

  end
end

