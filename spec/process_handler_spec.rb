RSpec.describe MainLoop::ProcessHandler do
  let(:bus){ MainLoop::Bus.new }
  let(:dispatcher){ MainLoop::Dispatcher.new(bus) }
  let(:status_success) { double(Process::Status, exitstatus: nil, termsig: nil, success?: true) }
  let(:status_failure) { double(Process::Status, exitstatus: nil, termsig: nil, success?: false) }
  subject(:handler){ described_class.new(dispatcher, 'test', retry_count: 0) }

  after(:each) do
    handler.instance_variable_set('@pid', nil)
    handler.instance_variable_set('@finished', nil)
    handler.instance_variable_set('@terminating_at', nil)
  end

  it { is_expected.to be_running }
  it { is_expected.not_to be_finished }

  describe '#reap' do
    describe 'status_success' do
      it do
        is_expected.to receive(:handle_retry)
        subject.reap(status_success)
        is_expected.to be_finished
        is_expected.not_to be_running
        is_expected.to be_success
      end
    end

    describe 'status_failure' do
      it do
        is_expected.to receive(:handle_retry)
        subject.reap(status_failure)
        is_expected.to be_finished
        is_expected.not_to be_running
        is_expected.not_to be_success
      end
    end
  end

  describe '#term' do
    let(:pid){ 111_111 }
    it 'nothing to do without pid' do
      is_expected.not_to receive(:terminating?)
      subject.term
    end

    it 'terminate when pid' do
      subject.instance_variable_set('@pid', pid)
      expect(Process).to receive(:kill).with('TERM', pid)

      is_expected.to receive(:terminating?).and_call_original
      subject.term
    end

    it 'kill when pid and terminating' do
      subject.instance_variable_set('@pid', pid)
      expect(Process).to receive(:kill).with('TERM', pid)
      expect(Process).to receive(:kill).with('KILL', pid)

      expect(subject.terminating?).to be_falsey
      subject.term
      expect(subject.terminating?).to be_truthy
      subject.term
    end
  end

  describe '#kill' do
    let(:pid){ 111_111 }
    it 'nothing to do without pid' do
      is_expected.not_to receive(:terminating?)
      subject.kill
    end

    it 'kill when pid' do
      subject.instance_variable_set('@pid', pid)
      expect(Process).to receive(:kill).with('KILL', pid)

      subject.kill
    end
  end

  describe '#id' do
    it 'returns @pid' do
      subject.instance_variable_set('@pid', 12345)
      expect(subject.id).to eq(12345)
    end

    it 'returns nil when @pid not set' do
      expect(subject.id).to be_nil
    end
  end

  describe '#run' do
    it 'does not run when terminating' do
      subject.instance_variable_set('@terminating_at', Time.now)
      expect(subject).not_to receive(:start_fork)
      subject.run
    end
  end

  describe '#term' do
    let(:pid){ 111_111 }

    it 'does not raise error when @on_term is set' do
      subject.instance_variable_set('@on_term', proc {})
      subject.instance_variable_set('@pid', pid)
      expect { subject.term }.not_to raise_error
    end
  end

  describe '#reap' do
    it 'logs with unknown status' do
      logger = double(Logger)
      subject.instance_variable_set('@logger', logger)
      expect(logger).to receive(:info).with(/exited.*unknown status/)
      subject.instance_variable_set('@pid', 123)
      subject.reap(nil)
    end

    it 'sets @finished and @pid = nil' do
      subject.instance_variable_set('@pid', 123)
      subject.reap(status_success)
      expect(subject.instance_variable_get('@finished')).to be_truthy
      expect(subject.instance_variable_get('@pid')).to be_nil
    end

    it 'does not call handle_retry when terminating' do
      subject.instance_variable_set('@terminating_at', Time.now)
      subject.instance_variable_set('@pid', 123)
      expect(subject).not_to receive(:handle_retry)
      subject.reap(status_success)
    end
  end
end
