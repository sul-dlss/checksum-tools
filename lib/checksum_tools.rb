module Checksum

  class Tools

    CHUNK_SIZE = 1048576 # 1M blocks
    DEFAULT_OPTS = { :overwrite => false, :recursive => false, :exclude => nil, :extension => '.digest' }

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
          raise NameError, "undefined digest class: #{key.to_s}"
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
      @opts = DEFAULT_OPTS
      if args.last.is_a?(Hash)
        @opts.merge!(args.pop)
      end
      @opts[:exclude] << digest_filename("*")
      args.each { |arg| self.class.digest_for(arg) }
      @digest_types = args
    end
  
    def digest_filename(filename)
      "#{filename}.#{opts[:extension].sub(/^\.+/,'')}"
    end
    
    def create_digest_files(base_dir, file_masks, &block)
      process_files(base_dir, file_masks) do |filename|
        yield(filename, -1, -1) if block_given?
        create_digest_file(filename, &block)
      end
    end
  
    def create_digest_file(filename, &block)
      digest_file = digest_filename(filename)
      if opts[:overwrite] or not File.exists?(digest_file)
        result = digest_file(filename, &block)
        File.open(digest_file,'w') do |cksum| 
          cksum.puts("#{File.basename(filename)}")
          result.each_pair do |type,hexdigest| 
            cksum.puts("#{type}::#{hexdigest}")
          end
        end
      end
    end
  
    def digest_files(base_dir, file_masks, &block)
      process_files(base_dir, file_masks) do |filename|
        yield(filename, -1, -1) if block_given?
        digest_file(filename, &block)
      end
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

    def verify_digest_files(base_dir, file_masks, &block)
      process_files(base_dir, file_masks) do |filename|
        yield(filename, -1, -1) if block_given?
        result = verify_digest_file(filename, &block)
        yield(filename, -1, 0, result)
        result
      end
    end

    def verify_digest_file(filename, &block)
      digest_file = digest_filename(filename)
      unless File.exists?(digest_file)
        return { :digest_file => false }
      end
      digest_data = File.read(digest_file).split(/\n/)
      unless File.basename(digest_data.shift) == File.basename(filename)
        warn "WARNING: Filename mismatch in #{digest_file}: #{File.basename(digest_data.shift)}"
      end
      hashes = digest_data.inject({}) do |collector,sum|
        (hash,digest) = sum.split(/::/,2)
        collector[hash.to_sym] = digest
        collector
      end
      verify_file(filename, hashes, &block)
    end
  
    def verify_file(filename, hashes, &block)
      with_types(hashes.keys) do
        actual = digest_file(filename, &block)
        result = {}
        actual.each_pair do |hash,digest|
          result[hash] = hashes[hash] == digest
        end
        result
      end
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
  
    def process_files(base_dir, include_masks = ["*"])
      unless block_given?
        raise ArgumentError, "no block given"
      end
    
      targets = []
      include_masks.each do |mask|
        targets += file_list(base_dir, mask)
      end
      targets.sort!
      targets.uniq!
      
      Array(opts[:exclude]).each do |mask|
        targets -= file_list(base_dir, mask)
      end
      targets.sort!
      targets.uniq!
      
      result = {}
      targets.sort.uniq.each do |filename|
        result[filename] = yield(filename)
      end
      return result
    end
  
    def with_types(new_types)
      old_types = @digest_types
      @digest_types = new_types
      begin
        return(yield)
      ensure
        @digest_types = old_types
      end
    end

  end

end

Checksum::Tools.register_digest(:md5,    'digest/md5')  { Digest::MD5.new       }
Checksum::Tools.register_digest(:sha1,   'digest/sha1') { Digest::SHA1.new      }
Checksum::Tools.register_digest(:sha256, 'digest/sha2') { Digest::SHA2.new(256) }
Checksum::Tools.register_digest(:sha384, 'digest/sha2') { Digest::SHA2.new(384) }
Checksum::Tools.register_digest(:sha512, 'digest/sha2') { Digest::SHA2.new(512) }
