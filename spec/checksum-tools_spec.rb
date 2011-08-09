require File.expand_path('../spec_helper', __FILE__)

describe Checksum::Tools do
  
  it "should create a Checksum::Tools::Local when given a local path" do
    path_info = Checksum::Tools.parse_path('/tmp')
    path_info.should == { :remote => { :user => nil, :host => nil }, :dir => '/tmp' }
    tool = Checksum::Tools.new(path_info,:md5,:sha1)
    tool.should be_a(Checksum::Tools::Local)
    tool.digest_types.should == [:md5,:sha1]
  end
  
  it "should create a Checksum::Tools::Remote when given a remote path" do
    path_info = Checksum::Tools.parse_path('user@remote:/tmp')
    path_info.should == { :remote => { :user => 'user', :host => 'remote' }, :dir => '/tmp' }
    tool = Checksum::Tools.new(path_info,:md5,:sha1)
    tool.should be_a(Checksum::Tools::Remote)
    tool.digest_types.should == [:md5,:sha1]
  end

end
