RSpec.describe MainLoop::ThreadHandler do
  let(:bus){ MainLoop::Bus.new }
  let(:dispatcher){ MainLoop::Dispatcher.new(bus) }
  subject(:handler){ described_class.new(dispatcher, 'test', retry_count: 0) }

  after(:each) do
    subject.instance_variable_set('@thread', nil)
    subject.instance_variable_set('@finished', nil)
    subject.instance_variable_set('@terminating_at', nil)
  end

  it { is_expected.to be_running }
  it { is_expected.not_to be_finished }

  describe '#reap' do
    it do
      is_expected.to receive(:handle_retry)
      subject.reap('status')
      is_expected.to be_finished
      is_expected.not_to be_running
      is_expected.not_to be_success
    end
  end

  describe '#term' do
    let(:thread){ double(Thread) }
    it 'nothing to do without thread' do
      is_expected.not_to receive(:terminating?)
      subject.term
    end

    it 'terminate when thread' do
      subject.instance_variable_set('@thread', thread)
      expect(thread).not_to receive(:kill)

      is_expected.to receive(:terminating?).and_call_original
      subject.term
    end

    it 'kill when thread and terminating' do
      subject.instance_variable_set('@thread', thread)
      expect(thread).to receive(:kill)

      expect(subject.terminating?).to be_falsey
      subject.term
      expect(subject.terminating?).to be_truthy
      subject.term
    end
  end

  describe '#kill' do
    let(:thread){ double(Thread) }
    it 'nothing to do without thread' do
      is_expected.not_to receive(:terminating?)
      subject.kill
    end

    it 'kill when thread' do
      subject.instance_variable_set('@thread', thread)
      expect(thread).to receive(:kill)

      subject.kill
    end
  end

  describe '#id' do
    it 'returns thread object_id' do
      thread = double(Thread, object_id: 45678)
      subject.instance_variable_set('@thread', thread)
      expect(subject.id).to eq('45678')
    end

    it 'returns empty string when @thread not set' do
      expect(subject.id).to eq('')
    end
  end

  describe '#run' do
    it 'does not run when terminating' do
      handler.instance_variable_set('@terminating_at', Time.now)
      expect(handler).not_to receive(:start_thread)
      handler.run
    end
  end

  describe '#term' do
    let(:thread) { double(Thread) }

    it 'does not raise error when @on_term is set' do
      handler.instance_variable_set('@on_term', proc {})
      handler.instance_variable_set('@thread', thread)
      expect { handler.term }.not_to raise_error
    end
  end

  describe '#reap' do
    it 'does not call handle_retry when terminating' do
      handler.instance_variable_set('@terminating_at', Time.now)
      expect(handler).not_to receive(:handle_retry)
      handler.reap(nil)
    end

    it 'sets @finished and @thread = nil' do
      handler.instance_variable_set('@thread', double('Thread'))
      handler.reap('status')
      expect(handler.instance_variable_get('@finished')).to be_truthy
      expect(handler.instance_variable_get('@thread')).to be_nil
    end

    it 'sets @success = false on reap' do
      handler.instance_variable_set('@thread', double('Thread'))
      handler.reap('status')
      expect(handler.instance_variable_get('@success')).to be_falsey
    end
  end
end
