require 'net/ssh'
require 'net/ssh/kerberos'
require 'net/sftp'

module Checksum::Tools
  
  class Remote < Base
    
    attr :digest_types
    attr :opts

    def initialize(host, user, *args)
      super(*args)
      @host = host
      @user = user
      @digest_length_cache = {}
    end
    
    def openssl
      opts[:openssl] || remote_properties[:openssl]
    end
    
    def sftp
      @sftp ||= Net::SFTP.start(@host, @user, :auth_methods => %w(gssapi-with-mic publickey hostbased))
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
      ssh.exec!(cmd).chomp
    end
    
    def digests
      resp = ''
      resp = exec! "#{openssl} dgst -h"
      resp.scan(/-(.+?)\s+to use the .+ message digest algorithm/).flatten.collect { |d| d.to_sym }
    end
  
    def digest_length(type)
      if @digest_length_cache[type].nil?
        resp = exec! "echo - | #{openssl} dgst -#{type}"
        @digest_length_cache[type] = resp.chomp.length
      end
      @digest_length_cache[type]
    end
    
    def digest_file(filename)
      if file_exists?(filename)
        size = file_size(filename)
        yield(filename, size, 0) if block_given?
        output = {}
        digest_types.each { |key| 
          resp = exec! "#{openssl} dgst -#{key} #{filename}"
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
          @remote_properties = { :openssl => 'openssl' }
        end
      end
      @remote_properties
    end
  end
  
end