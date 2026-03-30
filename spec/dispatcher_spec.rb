RSpec.describe MainLoop::Dispatcher do
  let(:bus){ MainLoop::Bus.new }
  let(:timeout){ rand }
  let(:handler){ double(MainLoop::Handler, id: rand(10_000).to_s, name: 'test') }
  subject(:dispatcher){ described_class.new(bus) }

  after(:each) { bus.close }

  it { is_expected.not_to be_terminating }
  it { is_expected.not_to be_need_force_kill }


  it '#reap' do
    is_expected.to receive(:reap_by_id).with(1, 2)
    is_expected.to receive(:reap_by_id).with(3, 4)

    subject.reap([[1, 2], [3, 4]])
  end

  it '#reap_by_id' do
    subject.add_handler(handler)
    expect(handler).to receive(:reap).with(4)

    subject.reap_by_id(1, 2)
    subject.reap_by_id(handler.id, 4)
  end

  describe '#add_handler' do
    it 'should change handlers size' do
      expect do
        subject.add_handler(handler)
      end.to change{ subject.handlers.size }.by(1)
    end

    it 'should change handlers size and terminate when term' do
      expect(handler).to receive(:term)
      dispatcher.term
      expect do
        subject.add_handler(handler)
      end.to change{ subject.handlers.size }.by(1)
    end
  end

  describe 'term' do
    before do
      expect(handler).to receive(:term)
      subject.add_handler(handler)
      subject.term
    end

    it 'first call' do
      expect(subject).to be_terminating
    end

    it 'second call' do
      expect(handler).to receive(:kill)
      subject.term
    end

    it { is_expected.not_to be_need_force_kill }
    it 'should be need force kill after a timeout' do
      subject.instance_variable_set('@terminating_at', Time.now - 100)
      is_expected.to be_need_force_kill
    end
  end

  describe '#tick' do
    before do
      subject.logger.level = Logger::INFO
      subject.add_handler(handler)
    end

    it 'should not to anything' do
      expect(dispatcher).not_to receive(:try_exit!)
      expect(dispatcher).not_to receive(:need_force_kill?)
      dispatcher.tick
    end

    it 'should try exit when terminating' do
      expect(handler).to receive(:term)
      dispatcher.term
      expect(dispatcher).to receive(:try_exit!)
      expect(dispatcher).to receive(:need_force_kill?)
      dispatcher.tick
    end

    it 'should force kill only once' do
      expect(handler).to receive(:term)
      dispatcher.term
      expect(dispatcher).to receive(:try_exit!).exactly(3)
      expect(dispatcher).to receive(:need_force_kill?).and_return(true)

      expect(handler).to receive(:kill)
      dispatcher.tick
      dispatcher.tick
      dispatcher.tick
    end
  end

  describe '#crash' do
    before do
      subject.instance_variable_set('@terminating_at', nil)
    end
    let(:handler2) { double(MainLoop::Handler, id: 'h2', name: 'test2', finished?: false) }

    it 'sets exit code to 3' do
      subject.crash
      expect(subject.instance_variable_get('@exit_code')).to eq(3)
    end

    it 'does not call term when already terminating' do
      subject.instance_variable_set('@terminating_at', Time.now - 1)
      expect(handler2).not_to receive(:term)
      subject.crash
    end
  end

  describe '#need_force_kill?' do
    it 'returns false when not terminating' do
      expect(subject.need_force_kill?).to be_falsey
    end

    it 'returns true when timeout exceeded' do
      subject.instance_variable_set('@terminating_at', Time.now - 100)
      expect(subject.need_force_kill?).to be_truthy
    end

    it 'returns false when timeout not exceeded' do
      subject.instance_variable_set('@terminating_at', Time.now - 0.5)
      expect(subject.need_force_kill?).to be_falsey
    end
  end

  describe '#pids' do
    let(:process_handler) { double(MainLoop::Handler, id: 'pid123', pid: 123) }
    let(:thread_handler) { double(MainLoop::Handler, id: 'thread456', pid: nil) }

    it 'returns list of pids from handlers' do
      subject.add_handler(process_handler)
      subject.add_handler(thread_handler)
      expect(subject.pids).to eq([123])
    end

    it 'handles missing pid' do
      subject.add_handler(thread_handler)
      expect(subject.pids).to eq([])
    end
  end

  describe '#try_exit!' do
    let(:handler2) { double(MainLoop::Handler, id: 'h2', name: 'test2', finished?: true, running?: false, success?: true) }
    let(:handler3) { double(MainLoop::Handler, id: 'h3', name: 'test3', finished?: true, running?: false, success?: true) }

    before do
      subject.add_handler(handler2)
      subject.add_handler(handler3)
    end

    it 'exits when all handlers finished' do
      expect { subject.try_exit! }.to raise_error(SystemExit)
    end

    it 'exits with 1 when not all success' do
      allow(handler3).to receive(:success?).and_return(false)
      expect { subject.try_exit! }.to raise_error(SystemExit)
    end

    it 'exits with @exit_code (3) when crash' do
      subject.instance_variable_set('@exit_code', 3)
      expect { subject.try_exit! }.to raise_error(SystemExit)
    end
  end
end

