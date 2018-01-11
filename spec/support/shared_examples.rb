shared_examples_for 'configurable subscriber worker' do
  describe '.configured?' do
    context 'for unconfigured class' do
      subject { FailingEventWorker.configured? }

      it { is_expected.to eq(false) }
    end

    context 'for configured class' do
      subject { MyEventWorker.configured? }

      it { is_expected.to eq(true) }
    end
  end

  describe '.perform_where_needed?' do
    context 'for delayed worker' do
      let(:klass) { MyDelayedWorker }
      subject { klass.perform_where_needed(event_data) }

      it 'uses perform_in to delay execution' do
        expect(klass).to receive(:perform_in).with(1, event_data)
        subject
      end
    end

    context 'for not delayed workers' do
      let(:klass) { MyEventWorker }
      subject { klass.perform_where_needed(event_data) }

      it 'uses perform_async to execute wherever' do
        expect(klass).to receive(:perform_async).with(event_data)
        subject
      end
    end
  end
end