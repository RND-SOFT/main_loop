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
end

