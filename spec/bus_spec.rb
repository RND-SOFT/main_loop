RSpec.describe MainLoop::Bus do
  subject(:bus){ described_class.new }
  let(:data){ rand(1_000_000_000).to_s }

  after(:each) { bus.close }

  describe '#initialize' do
    it { is_expected.to be_empty }
    it { is_expected.not_to be_closed }

    describe '#gets' do
      subject { bus.gets(0.1) }
      it { is_expected.to be_nil }
    end

    describe '#gets_nonblock' do
      subject { bus.gets_nonblock }
      it { is_expected.to be_nil }
    end
  end

  describe 'after puts(with data)' do
    before { bus.puts(data) }

    it { is_expected.not_to be_empty }

    describe '#gets' do
      subject { bus.gets(0.1) }
      it do
        is_expected.to eq(data)
        is_expected.not_to be_nil
      end
    end

    describe '#gets_nonblock' do
      subject { bus.gets_nonblock }
      it do
        is_expected.to eq(data)
        is_expected.not_to be_nil
      end
    end
  end

  describe 'after close' do
    before { bus.close }

    it { is_expected.to be_closed }
  end
end

