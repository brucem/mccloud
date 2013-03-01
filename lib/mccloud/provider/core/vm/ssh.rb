require 'mccloud/util/platform'

module Mccloud
  module Provider
    module Core
      module VmCommand

        def ssh_commandline_options(options)

          command_options = [
            "-q", #Suppress warning messages
             #           "-T", #Pseudo-terminal will not be allocated because stdin is not a terminal.
            "-t",
            "-p #{@port}",
            "-o UserKnownHostsFile=/dev/null",
            "-o StrictHostKeyChecking=no",
            #"-o IdentitiesOnly=yes",
            "-o VerifyHostKeyDNS=no",
            "-o ControlMaster=auto",
            "-o \"ControlPath=~/.ssh/master-%r@%h:%p\""
          ]
          unless @private_key_path.nil?
            command_options << "-i #{@private_key_path}"

          end
          if @agent_forwarding
            command_options << "-A"
          end
          commandline_options="#{command_options.join(" ")} ".strip

          unless options[:user]
            user_option=@user.nil? ? "" : "-l #{@user}"
          else
            user_option=@user.nil? ? "" : "-l #{options[:user]}"
          end

          return "#{commandline_options} #{user_option}"
        end

        def sudo(command=nil,options={})

          self.execute("#{sudo_string(command,options)}",options)
        end

        def sudo_string(command=nil,options={})
          prefix="sudo -H "

          # Check if we override the user in the options
          unless options[:user]
            prefix="" if self.user == "root"
          else
            prefix="" if options[:user] == "root"
          end
          return "#{prefix}#{command}"
        end

        def execute(command=nil,options={})
          ssh(command,options)
        end

        def fg_exec(ssh_command,options)
          # Some hackery going on here. On Mac OS X Leopard (10.5), exec fails
          # (GH-51). As a workaround, we fork and wait. On all other platforms,
          # we simply exec.
          pid = nil
          pid = fork if Mccloud::Util::Platform.leopard? || Mccloud::Util::Platform.tiger?

          env.logger.info "Executing internal ssh command"
          # Add terminal
          env.logger.info ssh_command+" -t"
          Kernel.exec ssh_command if pid.nil?
          Process.wait(pid) if pid
        end

        def bg_exec(ssh_command,options)
          result=ShellResult.new("","",-1)

          IO.popen("#{ssh_command}") { |p|
            p.each_line{ |l|
              result.stdout+=l
              print l unless options[:mute]
            }
            result.status=Process.waitpid2(p.pid)[1].exitstatus
            if result.status!=0
              env.ui.error "Exit status was not 0 but #{result.status}" unless options[:mute]
            end
          }
          return result
        end

        def ssh(command=nil,options={})

          # Command line options
          extended_command="#{command}"

          unless options.nil?
            extended_command="screen -R \\\"#{command}\\\"" unless options[:screen].nil?
          end

          host_ip=self.ip_address

          unless host_ip.nil? || host_ip==""
            ssh_command="ssh #{ssh_commandline_options(options)} #{host_ip} \"#{extended_command}\""

            unless options.nil? || options[:mute]
              env.ui.info "[#{@name}] - ssh -p #{@port} #{@user}@#{host_ip} \"#{command}\""
            end

            if command.nil? || command==""
              fg_exec(ssh_command,options)
            else
              unless options[:password]
                bg_exec(ssh_command,options)
              else
                env.ui.info "[#{@name}] - attempting password login"
                real_user = @user
                real_user = options[:user] if options[:user]

                if options[:user]
                    Net::SSH.start(host_ip, real_user, :password => options[:password] ) do |ssh2|
                        result = ssh2.exec!(command)
                        puts result
                    end
                else
                end
              end
            end

          else
            env.ui.error "Can't ssh into '#{@name} as we couldn't figure out it's ip-address"
          end
        end

      end #Module
    end #module
  end #Module
end #module
