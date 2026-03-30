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

  it '#reap_children with ECHILD error' do
    allow(dispatcher).to receive(:pids).and_return([1, 2, 3])
    allow(Process).to receive(:wait2).with(1, Process::WNOHANG).and_return(nil)
    allow(Process).to receive(:wait2).with(2, Process::WNOHANG).and_raise(Errno::ECHILD)
    allow(Process).to receive(:wait2).with(3, Process::WNOHANG).and_return(nil)
    allow(Process).to receive(:wait2).with(-1, Process::WNOHANG).and_return(nil)

    result = subject.reap_children
    expect(result).to include([2, nil])
    # wait2 возвращает nil, который не добавляется в результат
    # При ECHILD добавляем [pid, nil] как маркер, что процесс не найден
    expect(result.size).to eq(1)
  end

  it '#reap_children handles multiple ECHILD errors' do
    allow(dispatcher).to receive(:pids).and_return([10, 20, 30])
    allow(Process).to receive(:wait2).with(10, Process::WNOHANG).and_raise(Errno::ECHILD)
    allow(Process).to receive(:wait2).with(20, Process::WNOHANG).and_return([20, double('status')])
    allow(Process).to receive(:wait2).with(30, Process::WNOHANG).and_raise(Errno::ECHILD)
    allow(Process).to receive(:wait2).with(-1, Process::WNOHANG).and_return(nil)

    result = subject.reap_children
    # Проверяем, что все процессы были обработаны (ECHILd и успешные)
    expect(result).to include([10, nil])
    expect(result).to include([30, nil])
    expect(result.size).to eq(3)
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

  describe '#term' do
    it 'calls dispatcher.term' do
      expect(dispatcher).to receive(:term)
      expect(dispatcher).to receive(:terminating?).and_return(false)
      subject.term('term')
    end

    it 'does not call dispatcher.term when already terminating' do
      expect(dispatcher).to receive(:terminating?).and_return(true)
      expect(dispatcher).not_to receive(:term)
      subject.term('term')
    end
  end

  describe '#crash' do
    it 'calls dispatcher.crash' do
      expect(dispatcher).to receive(:crash)
      subject.crash('crash')
    end
  end

  describe '#signal' do
    it 'handles CLD signal' do
      expect(dispatcher).not_to receive(:term)
      subject.signal('sig:CLD')
    end
  end

  describe '#reap' do
    it 'calls dispatcher.reap_by_id with parsed values' do
      expect(dispatcher).to receive(:reap_by_id).with('123', '456')
      subject.reap('reap:123:456')
    end

    it 'parses empty status' do
      expect(dispatcher).to receive(:reap_by_id).with('123', nil)
      subject.reap('reap:123:')
    end
  end

  describe '#start_loop_forever' do
    it 'handles empty event with reaping' do
      allow(dispatcher).to receive(:pids).and_return([1, 2, 3])
      allow(subject).to receive(:wait2).and_return(nil)
      expect(dispatcher).to receive(:reap).with(an_instance_of(Array))
      expect(dispatcher).to receive(:tick)
      subject.start_loop_forever(timeout)
    end
  end

  describe '#reap_children' do
    it 'handles ECHILD error' do
      allow(dispatcher).to receive(:pids).and_return([1, 2, 3])
      allow(subject).to receive(:wait2).and_raise(Errno::ECHILD)
      result = subject.reap_children
      expect(result).to be_a(Array)
      expect(result.size).to eq(3)
    end

    it 'reaps all children with wait2(-1)' do
      allow(dispatcher).to receive(:pids).and_return([1])
      allow(subject).to receive(:wait2).with(1).and_return(nil)
      allow(subject).to receive(:wait2).with(-1).and_return(nil)
      subject.reap_children
      expect(subject).to have_received(:wait2).with(-1)
    end
  end
end

