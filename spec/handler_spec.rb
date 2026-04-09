RSpec.describe MainLoop::Handler do
  subject(:handler){ described_class.new(nil, 'test', retry_count: retry_count) }

  [0, 1, 2].each do |rc|
    describe "#handle_retry retry exaclty #{rc} times" do
      let(:retry_count){ rc }

      it "#{rc} times retry" do
        is_expected.to receive(:run).exactly(rc)
        is_expected.to receive(:publish).with(:term)
        (rc + 1).times do
          subject.handle_retry {}
        end
      end
    end
  end

  describe '#handle_retry retry forever' do
    let(:retry_count){ :unlimited }

    it 'retry forever' do
      is_expected.to receive(:run).exactly(5)
      is_expected.not_to receive(:publish).with(:term)
      5.times do
        subject.handle_retry {}
      end
    end
  end

  describe '#publish' do
    let(:bus){MainLoop::Bus.new }
    let(:dispatcher){ MainLoop::Dispatcher.new(bus) }
    subject(:handler){ described_class.new(dispatcher, 'test', retry_count: 0) }

    after(:each) { bus.close }

    it 'publishes to bus' do
      subject.publish('test_event')
      expect(bus.gets(0.1)).to eq('test_event')
    end
  end

  describe '#on_term' do
    let(:bus){ MainLoop::Bus.new }
    let(:dispatcher){ MainLoop::Dispatcher.new(bus) }
    let(:block){ proc { |pid| @called = true } }
    subject(:handler){ described_class.new(dispatcher, 'test', retry_count: 0) }

    it 'sets on_term block' do
      subject.on_term(&block)
      expect(subject.instance_variable_get('@on_term')).to eq(block)
    end
  end

  describe '#terminating?' do
    let(:bus){ MainLoop::Bus.new }
    let(:dispatcher){ MainLoop::Dispatcher.new(bus) }
    subject(:handler){ described_class.new(dispatcher, 'test', retry_count: 0) }

    it 'returns nil initially' do
      expect(handler.terminating?).to be_nil
    end
  end

  describe '#handle_retry with retry_count 0' do
    let(:retry_count){ 0 }
    let(:bus){ MainLoop::Bus.new }
    let(:dispatcher){ MainLoop::Dispatcher.new(bus) }
    subject(:handler){ described_class.new(dispatcher, 'test', retry_count: retry_count) }

    it 'does not retry and publishes term' do
      is_expected.not_to receive(:run)
      is_expected.to receive(:publish).with(:term)
      handler.handle_retry {}
    end
  end
end

