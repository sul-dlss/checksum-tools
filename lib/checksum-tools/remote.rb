require 'net/ssh'
require 'net/sftp'

begin
require 'net/ssh/kerberos'
rescue LoadError
  raise LoadError.new "Include 'net-ssh-kerberos' (ruby 1.8) or 'net-ssh-krb' (ruby 1.9) in your Gemfile"
end

module Checksum::Tools
  
  class Remote < Base
    
    attr :digest_types
    attr :opts

    def initialize(host, user, *args)
      super(*args)
      @host = host
      @user = user
      @digest_length_cache = {}
      unless (ssl = opts.delete(:openssl)).nil?
        begin
          remote_properties[:openssl] = ssl
        rescue ConfigurationError
          @remote_properties = { :openssl => ssl }
        end
        write_remote_properties
      end
    end

    def openssl
      remote_properties[:openssl] || remote_properties['openssl']
    end

    def sftp
      @sftp ||= begin
        auth_methods = %w(gssapi-with-mic publickey hostbased) if defined? Net::SSH::Kerberos
        auth_methods ||= %w(publickey hostbased)
        Net::SFTP.start(@host, @user, :auth_methods => auth_methods)
      end
    end
    
    def ssh
      result = sftp.session
      if block_given?
        channel = result.open_channel do |ch|
          yield(ch)
        end
        channel.wait
      end
      result
    end

    def exec!(cmd)
      result = ''
      ssh do |ch|
        ch.exec("bash -l") do |ch2, success|
          ch2.on_data { |c,data| result += data }
          ch2.send_data "#{cmd}\n"
          ch2.send_data "exit\n"
        end
      end
      result.chomp
    end
    
    def digests
      resp = ''
      resp = exec! "#{openssl} dgst -h 2>&1"
      resp.scan(/-(.+?)\s+to use the .+ message digest algorithm/).flatten.collect { |d| d.to_sym }
    end
  
    def digest_length(type)
      if @digest_length_cache[type].nil?
        resp = exec! "echo - | #{openssl} dgst -#{type}"
        @digest_length_cache[type] = resp.split(/\s/).last.chomp.length
      end
      @digest_length_cache[type]
    end
    
    def digest_file(filename)
      if file_exists?(filename)
        size = file_size(filename)
        yield(filename, size, 0) if block_given?
        output = {}
        digest_types.each { |key| 
          resp = exec! "#{openssl} dgst -#{key} $'#{filename.gsub(/[']/,'\\\\\'')}'"
          output[key] = resp.split(/\= /).last
        }
        yield(filename, size, size) if block_given?
        return output
      else
        raise Errno::ENOENT, filename
      end
    end
    
    protected
    
    def file_list(base_dir, *file_masks)
      path = ['*']
      path.unshift('**') if opts[:recursive]
      result = sftp.dir[base_dir, File.join(*path)]
      result.reject! { |f| f.directory? or (not file_masks.any? { |m| File.fnmatch?(m,File.basename(f.name)) }) }
      result.collect { |f| File.expand_path(File.join(base_dir, f.name)) }
    end

    def file_open(*args, &block)
      sftp.file.open(*args, &block)
    end
    
    def file_exists?(filename)
      sftp.stat!(filename)
      return true
    rescue Net::SFTP::StatusException
      return false
    end
    
    def file_size(filename)
      if file_exists?(filename)
        sftp.stat!(filename).size
      else
        raise Errno::ENOENT, filename
      end
    end
    
    def remote_properties
      if @remote_properties.nil?
        home_dir = exec!('echo $HOME')
        settings_file = File.join(home_dir,".checksum-tools-system")
        if file_exists?(settings_file)
          @remote_properties = YAML.load(file_read(settings_file))
        else
          raise ConfigurationError, "Checksum Tools not configured for #{@user}@#{host}. Please use the --openssl parameter to specify the location of the remote openssl binary."
        end
      end
      @remote_properties
    end

    def write_remote_properties
      home_dir = exec!('echo $HOME')
      settings_file = File.join(home_dir,".checksum-tools-system")
      file_open(settings_file, 'w') { |io| YAML.dump(remote_properties, io) }
      remote_properties
    end
    
  end
  
end