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
end

