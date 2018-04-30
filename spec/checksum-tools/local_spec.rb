require File.expand_path('../../spec_helper', __FILE__)
require 'tempfile'

describe Checksum::Tools::Local do

  describe "class methods" do

     it "should return false when registering an existing digest type" do
       expect(Checksum::Tools::Local.register_digest(:md5,'digest/md5') { Digest::MD5.new }).to be false
     end

     it "should return false when a digest class fails to load" do
       expect(Checksum::Tools::Local.register_digest(:sha999,'digest/sha999') { Digest::MD5.new }).to be false
     end

     it "should return a digest handler" do
       expect(Checksum::Tools::Local.digest_for(:md5)).to be_a(Digest::MD5)
     end

     it "should raise an error when an unsupported digest type is requested" do
       expect { Checksum::Tools::Local.digest_for(:sha999) }.to raise_error(ArgumentError)
     end

  end

  describe "instance methods" do

    before :each do
      @io = StringIO.new('abcdefghijklmnopqrstuvwxyz')
      @digests = { :md5 => 'c3fcd3d76192e4007dfb496cca67e13b', :sha1=>"32d10c7b8cf96570ca04ce37f2a19d84240d3a89" }
      @listener = double('listener')
      @tool = Checksum::Tools.new({:dir => '.'}, :md5, :sha1, :recursive => true)
    end

    it "should have the correct options" do
      expect(@tool.opts).to eq(:overwrite => false, :recursive => true, :exclude => ["*.digest"], :extension => '.digest')
    end

    it "should report correct digest lengths" do
      expect(@tool.digest_length(:md5)).to eq(32)
      expect(@tool.digest_length(:sha1)).to eq(40)
    end

    it "should generate digests for an IO stream" do
      expect(@listener).to receive(:progress).once.with(26)
      result = @tool.digest_stream(@io) { |*args| @listener.progress(*args) }
      expect(result).to eq(@digests)
    end

    it "should verify digests for an IO stream" do
      expect(@listener).to receive(:progress).once.with(26)
      result = @tool.verify_stream(@io, @digests) { |*args| @listener.progress(*args) }
      expect(result).to eq({ :md5 => true, :sha1 => true })
    end

  end

  describe "file operations" do

    before :all do
      @tmpdir = Dir.tmpdir
      tarfile = File.expand_path('../../test_data.tgz',__FILE__)
      `tar xzvf "#{tarfile}" -C "#{@tmpdir}" > /dev/null 2>&1`
      @dir = File.join(@tmpdir,'test_data')
    end

    after :all do
      FileUtils.rm_rf(File.join(@tmpdir,'test_data'))
    end

    before :each do
      @tool = Checksum::Tools.new({:dir => @dir}, :md5, :sha1, :recursive => true)
    end

    it "should calculate checksums for a file" do
      result = @tool.digest_file(File.join(@dir,'one/two/ignore.doc'))
      expect(result).to eq({ :md5 => 'a8b0d13fd645acc29b0dc2c4837e6f00', :sha1 => '8e129fe06c0679ce5a7f6e58d60cfd488512913a' })
      expect { @tool.digest_file(File.join(@dir,'one/two/nonexistent.txt')) }.to raise_error(Errno::ENOENT)
    end

    it "should generate checksums for a tree of files" do
      listener = double('listener')
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/report.pdf'),-1,-1)
      expect(listener).to receive(:progress).twice.with(File.join(@dir,'one/two/report.pdf'),134833,an_instance_of(Fixnum))
      expect(listener).to receive(:progress).once.with(File.join(@dir,'three/video.mp4'),-1,-1)
      expect(listener).to receive(:progress).exactly(4).times.with(File.join(@dir,'three/video.mp4'),2413046,an_instance_of(Fixnum))
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
      listener = double('listener')
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/report.pdf'),-1,-1)
      expect(listener).to receive(:progress).twice.with(File.join(@dir,'one/two/report.pdf'),134833,an_instance_of(Fixnum))
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/report.pdf'),-1,0,{ :md5 => true, :sha1 => true })
      expect(listener).to receive(:progress).once.with(File.join(@dir,'three/video.mp4'),-1,-1)
      expect(listener).to receive(:progress).exactly(4).times.with(File.join(@dir,'three/video.mp4'),2413046,an_instance_of(Fixnum))
      expect(listener).to receive(:progress).once.with(File.join(@dir,'three/video.mp4'),-1,0,{ :md5 => true, :sha1 => true })
      @tool.verify_digest_files(@dir, ['*.pdf','*.mp4']) do
         |*args| listener.progress(*args)
      end
    end

    it "should fail verification for a tree of files" do
      File.open(File.join(@dir,'three/video.mp4.digest'),'w') { |f| f.write("MD5(video.mp4)= 9023e975b52be97a4ef6ad4e25e2ef79\nSHA1(video.mp4)= ce828086b63e6b351d9fb6d6bc2b0838725bdf39\n") }
      listener = double('listener')
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/report.pdf'),-1,-1)
      expect(listener).to receive(:progress).twice.with(File.join(@dir,'one/two/report.pdf'),134833,an_instance_of(Fixnum))
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/report.pdf'),-1,0,{ :md5 => true, :sha1 => true })
      expect(listener).to receive(:progress).once.with(File.join(@dir,'three/video.mp4'),-1,-1)
      expect(listener).to receive(:progress).exactly(4).times.with(File.join(@dir,'three/video.mp4'),2413046,an_instance_of(Fixnum))
      expect(listener).to receive(:progress).once.with(File.join(@dir,'three/video.mp4'),-1,0,{ :md5 => true, :sha1 => false })
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/ignore.doc'),-1,-1)
      expect(listener).to receive(:progress).once.with(File.join(@dir,'one/two/ignore.doc'),-1,0,{ :digest_file => false })
      @tool.verify_digest_files(@dir, ['*']) do
         |*args| listener.progress(*args)
      end
    end

  end

end
