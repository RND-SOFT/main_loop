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

  describe '#wait_for_event' do
    before { bus.puts(data) }

    it 'returns io array when data available' do
      result = bus.wait_for_event(0.1)
      expect(result).not_to be_nil
      expect(result[0]).to be_a(Array)
    end
  end

  describe '#gets with timeout' do
    it 'returns nil when timeout' do
      expect(bus.gets(0.01)).to be_nil
    end
  end

  describe '#gets_nonblock with multiple chunks' do
    before do
      bus.puts('line1')
      bus.puts('line2')
    end

    it 'reads multiple lines' do
      expect(bus.gets_nonblock).to eq('line1')
      expect(bus.gets_nonblock).to eq('line2')
    end
  end

  describe '#puts after close' do
    it 'raises IOError on closed stream' do
      bus.close
      expect { bus.puts('test') }.to raise_error(IOError, /closed stream/)
    end
  end
end

