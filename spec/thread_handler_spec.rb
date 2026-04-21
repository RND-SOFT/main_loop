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
    let(:thread) { double(Thread, :[] => :normal) }

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
      handler.instance_variable_set('@thread', double(Thread, :[] => :normal))
      handler.reap('status')
      expect(handler.instance_variable_get('@finished')).to be_truthy
      expect(handler.instance_variable_get('@thread')).to be_nil
    end

    it 'sets @success = false on reap if exit_reason not :normal' do
      handler.instance_variable_set('@thread', double(Thread, :[] => nil))
      handler.reap('status')
      expect(handler.instance_variable_get('@success')).to be_falsey
    end

    it 'sets @success = true on reap if exit_reason :normal' do
      handler.instance_variable_set('@thread', double(Thread, :[] => :normal))
      handler.reap('status')
      expect(handler.instance_variable_get('@success')).to be_truthy
    end
  end

  describe 'integration' do
    let(:logger) { Logger.new(nil) }
    let(:loop_obj) { MainLoop::Loop.new(bus, dispatcher, logger: logger) } 

    # Ожидание условия с таймаутом (без фиксированного sleep)
    def wait_for(timeout: 1)
      start = Time.now
      until yield
        raise "Condition not met within #{timeout} seconds" if Time.now - start > timeout
        Thread.pass
      end
    end

    # Образцовый поток, который работает в цикле и останавливается по on_term
    def sample_handler(dispatcher, logger, name: 'sample')
      MainLoop::ThreadHandler.new(dispatcher, name, retry_count: 0, logger: logger) do |h|
        stopped = false
        h.on_term { stopped = true }
        loop { break if stopped; sleep 0.05 }
      end
    end

    context 'when second thread completes successfully' do
      it 'both success? true and exit status 0' do
        handler1 = sample_handler(dispatcher, logger)

        handler2 = MainLoop::ThreadHandler.new(dispatcher, 'fast', retry_count: 0, logger: logger) do
          4 + 4   # мгновенный успех
        end

        # Запускаем цикл в отдельном потоке, чтобы можно было управлять
        loop_thread = Thread.new do
          expect { loop_obj.run(2) }.to raise_error(SystemExit) do |error|
            @exit_status = error.status
          end
        end

        wait_for { handler2.finished? }
        wait_for { handler1.finished? }

        # Даём время на обработку reap и exit
        loop_thread.join

        expect(@exit_status).to eq(0)
        expect(handler1.success?).to be true
        expect(handler2.success?).to be true
      end
    end

    context 'when second thread is killed' do
      it 'first success? true, second false, exit status 1' do
        handler1 = sample_handler(dispatcher, logger)

        handler2 = MainLoop::ThreadHandler.new(dispatcher, 'killed', retry_count: 0, logger: logger) do
          loop { sleep 0.1 }
        end

        loop_thread = Thread.new do
          expect { loop_obj.run(2) }.to raise_error(SystemExit) do |error|
            @exit_status = error.status
          end
        end

        wait_for { handler1.running? && handler2.running? }

        Thread.new do
          handler2.thread.kill
        end

        wait_for { handler2.finished? }
        wait_for { handler1.finished? }

        loop_thread.join

        expect(@exit_status).to eq(1)
        expect(handler1.success?).to be true
        expect(handler2.success?).to be false
      end
    end

    context 'when second thread raises an error' do
      it 'first success? true, second false, exit status 1' do
        handler1 = sample_handler(dispatcher, logger)

        handler2 = MainLoop::ThreadHandler.new(dispatcher, 'error', retry_count: 0, logger: logger) do
          sleep 0.2
          raise 'Test error'
        end

        loop_thread = Thread.new do
          expect { loop_obj.run(2) }.to raise_error(SystemExit) do |error|
            @exit_status = error.status
          end
        end

        wait_for { handler2.finished? }
        wait_for { handler1.finished? }

        loop_thread.join

        expect(@exit_status).to eq(1)
        expect(handler1.success?).to be true
        expect(handler2.success?).to be false
      end
    end
  end
end
