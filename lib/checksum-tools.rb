module Checksum
  module Tools
    VERSION = "1.0.5"
    
    CHUNK_SIZE = 1048576 # 1M blocks
    DEFAULT_OPTS = { :overwrite => false, :recursive => false, :exclude => [], :extension => '.digest' }

    autoload :Local, File.join(File.dirname(__FILE__), File.basename(__FILE__, '.rb'), 'local')
    autoload :Remote, File.join(File.dirname(__FILE__), File.basename(__FILE__, '.rb'), 'remote')
    
    class Exception < ::Exception; end
    class ConfigurationError < Exception; end
    
    class << self
      def new(path_info, *args)
        remote = path_info[:remote]
        if remote.nil? or remote[:host].nil?
          Local.new(*args)
        else
          Remote.new(remote[:host],remote[:user],*args)
        end
      end
    
      def parse_path(path)
        user,host,dir = path.to_s.scan(/^(?:(.+)@)?(?:(.+):)?(?:(.+))?$/).flatten
        dir ||= '.'
        result = { :remote => { :user => user, :host => host }, :dir => dir }
        return result
      end
    end
    
    class Base
      attr_reader :host
      
      def initialize(*args)
        @opts = DEFAULT_OPTS
        if args.last.is_a?(Hash)
          @opts.merge!(args.pop)
        end
        @opts[:exclude] << digest_filename("*")
        @opts[:exclude].uniq!
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
        if File.expand_path(filename) == File.expand_path(digest_file)
          raise ArgumentError, "Digest file #{digest_file} will clobber content file #{filename}!"
        end
        if opts[:overwrite] or not file_exists?(digest_file)
          result = digest_file(filename, &block)
          file_open(digest_file,'w') do |cksum|
            result.each_pair do |type,hexdigest| 
              cksum.puts("#{type.to_s.upcase}(#{File.basename(filename)})= #{hexdigest}")
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
        unless file_exists?(digest_file)
          return { :digest_file => false }
        end

        hashes = {}
        digest_data = file_read(digest_file)

        ext_type = File.extname(digest_file)[1..-1].downcase.to_sym
        # Check to see if the digest file extension implies a specific digest type (e.g., .md5)
        if digests.include?(ext_type)
          # Find a hex value of the correct length in the digest file
          len = self.digest_length(ext_type)
          digest = digest_data.scan(/\b((?:[0-9a-f]{4})+)\b/im).flatten.find { |d| d.length == len }
          hashes[ext_type] = digest
        else
          digest_data = digest_data.split(/\n/)
          hashes = digest_data.inject({}) do |collector,sum|
            (hash,hashed_fname,digest) = sum.scan(/(.+)\((.+)\)= (.+)/).flatten
            unless File.basename(hashed_fname) == File.basename(filename)
              warn "WARNING: Filename mismatch in #{digest_file}: #{File.basename(hashed_fname)}"
            end
            collector[hash.downcase.to_sym] = digest
            collector
          end
        end
        verify_file(filename, hashes, &block)
      end

      def verify_file(filename, hashes, &block)
        with_types(hashes.keys) do
          actual = digest_file(filename, &block)
          result = {}
          actual.each_pair do |hash,digest|
            result[hash] = hashes[hash].downcase == digest.downcase
          end
          result
        end
      end

      protected

      def glob_to_re(glob)
        replacements = [
          [/\./,'##DOT##'],[/\\\*/,'##STAR##'],[/\\\?/,'##QUEST##'],
          [/\*/,'.*'],[/\?/,'.'],
          [/##STAR##/,'\*'],[/##QUEST##/,'\?'],[/##DOT##/,'\.']
        ]
        result = glob.dup
        replacements.each { |args| result.gsub!(*args) }
        Regexp.new(result)
      end
      
      def file_read(filename)
        if file_exists?(filename)
          result = ''
          file_open(filename) { |io| result = io.read }
          return result
        else
          raise Errno::ENOENT, filename
        end
      end

      def process_files(base_dir, include_masks = ["*"])
        unless block_given?
          raise ArgumentError, "no block given"
        end
        
        excludes = Array(opts[:exclude]).collect { |ex| glob_to_re(ex) }
        targets = file_list(base_dir, *include_masks).reject { |f| excludes.any? { |re| f.match(re) } }
        targets.sort!
        targets.uniq!
      
        result = {}
        targets.each do |filename|
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
end
