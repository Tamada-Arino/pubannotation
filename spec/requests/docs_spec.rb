require 'rails_helper'

RSpec.describe "Docs", type: :request do
  describe "GET /docs(.:format)" do
    subject { response }

    context 'when no docs' do
      before { get "/docs.json" }

      it { is_expected.to have_http_status(200) }
      it { expect(response.body).to eq([].to_json) }
    end

    context 'when there are docs' do
      before do
        create(:doc)
        get "/docs.json"
      end

      it { is_expected.to have_http_status(200) }
      it 'returns the doc data' do
        expected_data = [{
                           sourcedb: "PubMed",
                           sourceid: Doc.last.sourceid,
                           url: "http://test.pubannotation.org/docs/sourcedb/PubMed/sourceid/#{Doc.last.sourceid}",
                         }]

        expect(response.body).to eq(expected_data.to_json)
      end
    end
  end
end
