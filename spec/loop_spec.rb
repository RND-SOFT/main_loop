RSpec.describe MainLoop::Loop do
  let(:bus){ MainLoop::Bus.new }
  let(:dispatcher){ double(MainLoop::Dispatcher) }
  let(:timeout){ rand }
  subject(:loop){ described_class.new(bus, dispatcher) }

  after(:each) { bus.close }

  it '#run' do
    is_expected.to receive(:install_signal_handlers).with(bus)
    is_expected.to receive(:start_loop_forever).with(timeout)
    subject.run(timeout)
  end

  describe '#signal' do
    MainLoop::TERM_SIGNALS.each do |sig|
      it sig.to_s do
        expect(dispatcher).to receive(:term)
        subject.signal("sig:#{sig}")
      end
    end
  end

  it 'reap' do
    id = rand(10_000_000).to_s
    status = rand(10_000_000).to_s
    expect(dispatcher).to receive(:reap_by_id).with(id, status)
    subject.reap("read:#{id}:#{status}")
  end

  it '#reap_children' do
    expect(dispatcher).to receive(:pids).and_return([1, 2, 3])
    is_expected.to receive(:wait2).with(1)
    is_expected.to receive(:wait2).with(2)
    is_expected.to receive(:wait2).with(3)
    is_expected.to receive(:wait2).with(-1)
    subject.reap_children
  end

  describe '#start_loop_forever' do
    before do
      allow(dispatcher).to receive(:pids).and_return([1, 2, 3])
      allow(subject).to receive(:wait2).and_return(nil)
      expect(dispatcher).to receive(:reap).at_least(1)
      expect(dispatcher).to receive(:tick).at_least(1)
    end

    it 'must leave by timeout' do
      subject.start_loop_forever(timeout)
    end

    it 'terminate by term' do
      is_expected.to receive(:term).with('term')
      bus.puts(:term)
      subject.start_loop_forever(timeout)
    end

    it 'signal by sig:CLD' do
      is_expected.to receive(:signal).with('sig:CLD')
      bus.puts('sig:CLD')
      subject.start_loop_forever(timeout)
    end

    it 'reap by reap:id:status' do
      is_expected.to receive(:reap).with('reap:id:status')
      bus.puts('reap:id:status')
      subject.start_loop_forever(timeout)
    end
  end
end

