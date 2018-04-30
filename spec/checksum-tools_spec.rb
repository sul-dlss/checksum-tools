require File.expand_path('../spec_helper', __FILE__)

describe Checksum::Tools do
  
  it "should create a Checksum::Tools::Local when given a local path" do
    path_info = Checksum::Tools.parse_path('/tmp')
    expect(path_info).to eq({ :remote => { :user => nil, :host => nil }, :dir => '/tmp' })
    tool = Checksum::Tools.new(path_info,:md5,:sha1)
    expect(tool).to be_a(Checksum::Tools::Local)
    expect(tool.digest_types).to eq([:md5,:sha1])
  end
  
  it "should create a Checksum::Tools::Remote when given a remote path" do
    path_info = Checksum::Tools.parse_path('user@remote:/tmp')
    expect(path_info).to eq({ :remote => { :user => 'user', :host => 'remote' }, :dir => '/tmp' })
    tool = Checksum::Tools.new(path_info,:md5,:sha1)
    expect(tool).to be_a(Checksum::Tools::Remote)
    expect(tool.digest_types).to eq([:md5,:sha1])
  end

end
