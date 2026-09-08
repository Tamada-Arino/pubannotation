# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MediaDocCreationService do
  let(:user) { create(:user).tap { |u| u.confirm } }
  let(:project) { create(:project, user: user) }
  let(:medium) { create(:medium) }

  describe '#save_doc' do
    it 'creates a doc with the given body, linked to the medium and the project' do
      service = described_class.new(
        project: project,
        medium: medium,
        user: user,
        attributes: { source: nil, sourcedb: 'Example', sourceid: '001' }
      )

      doc = service.save_doc('A generated body.')

      expect(doc).to be_persisted
      expect(doc.body).to eq('A generated body.')
      expect(doc.sourcedb).to eq("Example@#{user.username}")
      expect(doc.sourceid).to eq('001')
      expect(doc.medium).to eq(medium)
      expect(project.docs).to include(doc)
    end
  end
end
