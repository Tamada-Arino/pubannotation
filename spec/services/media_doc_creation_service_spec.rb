# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MediaDocCreationService do
  let(:user) { create(:user).tap { |u| u.confirm } }
  let(:project) { create(:project, user: user) }
  let(:medium) { create(:medium, media_type: :audio, content_type: 'audio/mpeg') }
  let(:task) { create(:media_transcription_task, medium: medium) }
  let(:media_transcript) do
    create(:media_transcript, medium: medium, media_transcription_task: task, text: 'A generated body.')
  end
  let(:attributes) { { source: nil, sourcedb: 'Example', sourceid: '001' } }

  describe '.call' do
    it "creates a doc from the transcript's text, linked to the medium and the project" do
      doc = described_class.call(project, medium, user, attributes, media_transcript, task)

      expect(doc).to be_persisted
      expect(doc.body).to eq('A generated body.')
      expect(doc.sourcedb).to eq("Example@#{user.username}")
      expect(doc.sourceid).to eq('001')
      expect(doc.medium).to eq(medium)
      expect(project.docs).to include(doc)
    end

    it 'links the media_transcript to the created doc' do
      doc = described_class.call(project, medium, user, attributes, media_transcript, task)

      expect(media_transcript.reload.doc).to eq(doc)
    end

    it 'marks the media_transcription_task succeeded' do
      task.update!(status: 'processing')

      described_class.call(project, medium, user, attributes, media_transcript, task)

      expect(task.reload).to be_succeeded
    end

    context 'when linking the transcript to the doc fails' do
      it 'raises and does not link the doc to the project' do
        allow(media_transcript).to receive(:update!).and_raise(StandardError, 'update blew up')

        expect {
          described_class.call(project, medium, user, attributes, media_transcript, task)
        }.to raise_error(StandardError, 'update blew up')

        doc = Doc.find_by(sourcedb: "Example@#{user.username}", sourceid: '001')
        expect(doc).to be_present
        expect(project.docs.reload).not_to include(doc)
      end
    end
  end
end
