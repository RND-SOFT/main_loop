RSpec.describe MainLoop::ThreadHandler do
  let(:bus){ MainLoop::Bus.new }
  let(:dispatcher){ MainLoop::Dispatcher.new(bus) }
  subject(:handler){ described_class.new(dispatcher, 'test', retry_count: 0) }

  it { is_expected.to be_running }
  it { is_expected.not_to be_finished }

  describe '#reap' do
    it do
      is_expected.to receive(:handle_retry)
      subject.reap("status")
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
end

