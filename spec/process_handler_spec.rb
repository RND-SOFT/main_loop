RSpec.describe MainLoop::ProcessHandler do
  let(:bus){ MainLoop::Bus.new }
  let(:dispatcher){ MainLoop::Dispatcher.new(bus) }
  let(:status_success) { double(Process::Status, exitstatus: nil, termsig: nil, success?: true) }
  let(:status_failure) { double(Process::Status, exitstatus: nil, termsig: nil, success?: false) }
  subject(:handler){ described_class.new(dispatcher, 'test', retry_count: 0) }

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
end

