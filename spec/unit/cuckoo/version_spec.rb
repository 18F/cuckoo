RSpec.describe Cuckoo::VERSION do
  it 'should have a version' do
    expect(Cuckoo::VERSION).to match(/\A\d+\.\d+\.\d+(-[a-z0-9]+)?\z/)
  end
end
