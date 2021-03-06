require File.expand_path('../../spec_helper', __FILE__)
require 'tempfile'

describe Checksum::Tools::Remote do

  describe "file operations" do

    before :all do
      @mock_sftp = Class.new do
        def dir
          Class.new do
            def self.[](*args)
              Dir[File.join(*args)].collect { |s|
                name = s[args.first.length..-1]
                stat = File.stat(s)
                type = stat.mode & 0040000 != 0 ? Net::SFTP::Protocol::V04::Attributes::T_DIRECTORY : Net::SFTP::Protocol::V04::Attributes::T_REGULAR
                attrs = {
                  :type => type,
                  :size => stat.size,
                  :owner => stat.uid,
                  :group => stat.gid,
                  :permissions => stat.mode & 0777,
                  :atime => stat.atime,
                  :createtime => stat.ctime,
                  :mtime => stat.mtime
                }
                Net::SFTP::Protocol::V04::Name.new(name, Net::SFTP::Protocol::V04::Attributes.new(attrs))
              }
            end
          end
        end
        def file
          File
        end
        def stat!(*args)
          File.stat(*args)
        rescue Errno::ENOENT
          raise Net::SFTP::StatusException.new(Net::SFTP::Response.new(nil, :code => 2, :type => 101), 'no such file')
        end
      end

      @mock_ssh = Class.new do
        def exec!(c)
          %x[#{c} 2>/dev/null]
        end
      end

      @tmpdir = Dir.tmpdir
      tarfile = File.expand_path('../../test_data.tgz',__FILE__)
      `tar xzvf "#{tarfile}" -C "#{@tmpdir}" > /dev/null 2>&1`
      @dir = File.join(@tmpdir,'test_data')
    end

    after :all do
      FileUtils.rm_rf(File.join(@tmpdir,'test_data'))
    end

    before :each do
      sftp = @mock_sftp.new
      ssh = @mock_ssh.new
      @tool = Checksum::Tools.new(Checksum::Tools.parse_path("ckuser@example.edu:#{@dir}"), :md5, :sha1, :recursive => true)
      allow(@tool).to receive(:remote_properties).and_return({ :openssl => 'openssl' })
      allow(@tool).to receive(:sftp).and_return(sftp)
      allow(@tool).to receive(:ssh).and_return(ssh)
      # KLUDGE ALERT: We can't mock an entire asynchronous SSH session, so we're
      #               stubbing Checksum::Tools::Remote#exec! which is one of the
      #               methods we should be testing!
      allow(@tool).to receive(:exec!) { |c| %x[#{c} 2>/dev/null].chomp }
    end

    after :each do
      @tool = nil
    end

    it "should be of the correct type" do
      expect(@tool).to be_a(Checksum::Tools::Remote)
    end

    it "should report correct digest lengths" do
      expect(@tool.digest_length(:md5)).to eq(32)
      expect(@tool.digest_length(:sha1)).to eq(40)
    end

    it "should report on file size" do
      expect(@tool.send(:file_size,File.join(@dir,'one/two/report.pdf'))).to eq(134833)
      expect { @tool.send(:file_size,File.join(@dir,'one/two/nonexistent.txt')) }.to raise_error(Errno::ENOENT)
    end

    it "should calculate checksums for a file" do
      pending('Checksum::Tools::Remote#exec! is stubbed and does not execute under CI') if ENV['TRAVIS']
      result = @tool.digest_file(File.join(@dir,'one/two/ignore.doc'))
      expect(result).to eq({ :md5 => 'a8b0d13fd645acc29b0dc2c4837e6f00', :sha1 => '8e129fe06c0679ce5a7f6e58d60cfd488512913a' })
      expect { @tool.digest_file(File.join(@dir,'one/two/nonexistent.txt')) }.to raise_error(Errno::ENOENT)
    end

    it "should generate checksums for a tree of files" do
      pending('Checksum::Tools::Remote#exec! is stubbed and does not execute under CI') if ENV['TRAVIS']
      listener = double('listener')
      expect(listener).to receive(:progress).exactly(6).times.with(an_instance_of(String),an_instance_of(Fixnum),an_instance_of(Fixnum))
      @tool.create_digest_files(@dir, ['*.pdf','*.mp4']) do
         |*args| listener.progress(*args)
      end
      strings = File.read(File.join(@dir,'one/two/report.pdf.digest')).split(/\n/)
      expect(strings).to include("MD5(report.pdf)= fda5eab2335987f56d7d3abe53734295")
      expect(strings).to include("SHA1(report.pdf)= 56ea04102e0388de9b9c31c6db8aebbff67671c1")

      strings = File.read(File.join(@dir,'three/video.mp4.digest')).split(/\n/)
      expect(strings).to include("MD5(video.mp4)= 9023e975b52be97a4ef6ad4e25e2ef79")
      expect(strings).to include("SHA1(video.mp4)= ce828086b63e6b351d9fb6d6bc2b0838725bdf37")

      expect(File.exists?(File.join(@dir,'one/two/ignore.doc.digest'))).to be false
    end

    it "should pass verification for a tree of files" do
      pending('Checksum::Tools::Remote#exec! is stubbed and does not execute under CI') if ENV['TRAVIS']
      listener = double('listener')
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/report.pdf'),-1,-1)
      expect(listener).to receive(:progress).twice.with(File.join(@dir,'one/two/report.pdf'),134833,an_instance_of(Fixnum))
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/report.pdf'),-1,0,{ :md5 => true, :sha1 => true })
      expect(listener).to receive(:progress).once.with(File.join(@dir,'three/video.mp4'),-1,-1)
      expect(listener).to receive(:progress).twice.with(File.join(@dir,'three/video.mp4'),2413046,an_instance_of(Fixnum))
      expect(listener).to receive(:progress).once.with(File.join(@dir,'three/video.mp4'),-1,0,{ :md5 => true, :sha1 => true })
      @tool.verify_digest_files(@dir, ['*.pdf','*.mp4']) do
         |*args| listener.progress(*args)
      end
    end

    it "should fail verification for a tree of files" do
      pending('Checksum::Tools::Remote#exec! is stubbed and does not execute under CI') if ENV['TRAVIS']
      File.open(File.join(@dir,'three/video.mp4.digest'),'w') { |f| f.write("MD5(video.mp4)= 9023e975b52be97a4ef6ad4e25e2ef79\nSHA1(video.mp4)= ce828086b63e6b351d9fb6d6bc2b0838725bdf39\n") }
      listener = double('listener')
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/report.pdf'),-1,-1)
      expect(listener).to receive(:progress).twice.with(File.join(@dir,'one/two/report.pdf'),134833,an_instance_of(Fixnum))
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/report.pdf'),-1,0,{ :md5 => true, :sha1 => true })
      expect(listener).to receive(:progress).once.with(File.join(@dir,'three/video.mp4'),-1,-1)
      expect(listener).to receive(:progress).twice.with(File.join(@dir,'three/video.mp4'),2413046,an_instance_of(Fixnum))
      expect(listener).to receive(:progress).once.with(File.join(@dir,'three/video.mp4'),-1,0,{ :md5 => true, :sha1 => false })
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/ignore.doc'),-1,-1)
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/ignore.doc'),-1,0,{ :digest_file => false })
      @tool.verify_digest_files(@dir, ['*']) do
         |*args| listener.progress(*args)
      end
    end

  end

end
