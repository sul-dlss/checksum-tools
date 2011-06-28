module Checksum::Tools

  class Local < Base

    class << self
      @@digests = {}
      
      def register_digest(key, file, &block)
        if @@digests.has_key?(key)
          return false
        else
          begin
            require file
            @@digests[key] = block
            return key
          rescue LoadError
            return false
          end
        end
      end

      def digest_for(key)
        handler = @@digests[key]
        if handler.nil?
          raise ArgumentError, "undefined digest class: #{key.to_s}"
        end
        return handler.call()
      end
    
      def digests
        @@digests.keys
      end
    end

    attr :digest_types
    attr :opts
    
    def initialize(*args)
      super(*args)
      @digest_types.each { |type| self.class.digest_for(type) }
    end
  
    def digests
      self.class.digests
    end
    
    def digest_file(filename)
      if File.exists?(filename)
        size = File.size?(filename)
        block = block_given? ? lambda { |pos| yield(filename, size, pos) } : nil
        File.open(filename, 'r') do |io|
          yield(filename, size, 0) if block_given?
          return digest_stream(io, &block)
        end
      else
        raise Errno::ENOENT, filename
      end
    end
  
    def digest_stream(io)
      output = digest_types.inject({}) { |collector,key| collector[key] = self.class.digest_for(key); collector }
      io.rewind
      while chunk = io.read(CHUNK_SIZE)
        output.values.each do |digest|
          digest << chunk
        end
        if block_given?
          yield(io.pos)
        end
      end
      output.each_pair do |type,digest|
        output[type] = digest.hexdigest
      end
      return output
    end

    def verify_stream(io, hashes, &block)
      with_types(hashes.keys) do
        actual = digest_stream(io, &block)
        result = {}
        actual.each_pair do |hash,digest|
          result[hash] = hashes[hash] == digest
        end
        result
      end
    end

    protected
    
    def file_list(base_dir, file_mask)
      path = [base_dir, file_mask]
      path.insert(1,'**') if opts[:recursive]
      result = Dir[File.join(*path)].reject { |f| File.directory?(f) }
      return result
    end
  
    def file_open(*args, &block)
      File.open(*args, &block)
    end
    
    def file_exists?(filename)
      File.exists?(filename)
    end
    
    def file_size(filename)
      File.size(filename)
    end
    
  end

end

Checksum::Tools::Local.register_digest(:md5,    'digest/md5')  { Digest::MD5.new       }
Checksum::Tools::Local.register_digest(:sha1,   'digest/sha1') { Digest::SHA1.new      }
Checksum::Tools::Local.register_digest(:sha256, 'digest/sha2') { Digest::SHA2.new(256) }
Checksum::Tools::Local.register_digest(:sha384, 'digest/sha2') { Digest::SHA2.new(384) }
Checksum::Tools::Local.register_digest(:sha512, 'digest/sha2') { Digest::SHA2.new(512) }
