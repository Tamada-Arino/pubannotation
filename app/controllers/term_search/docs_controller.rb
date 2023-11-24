# frozen_string_literal: true

module TermSearch
  class DocsController < ApplicationController
    include ArrayParameterConcern

    def index
      base_project = Project.accessible(current_user).find_by!(name: params[:base_project]) if params[:base_project].present?
      docs = base_project.present? ? base_project.docs : Doc.all

      if params[:terms].present?
        docs = docs.with_terms to_array(params[:terms]),
                               current_user,
                               to_array(params[:predicates]),
                               to_array(params[:projects])
      end

      doc_fields = docs.select('sourcedb', 'sourceid')
                       .simple_paginate(params[:page]&.to_i || 1, params[:per]&.to_i || 10)
                       .map(&:to_list_hash)

      respond_to do |format|
        format.json { send_doc_data(doc_fields.to_json, 'docs.json', 'application/json') }
        format.tsv { send_doc_data(Doc.hash_to_tsv(doc_fields), 'docs.tsv', 'text/tab-separated-values') }
      end
    end

    private

    def send_doc_data(data, filename, type)
      send_data data,
                filename:,
                type:,
                disposition: 'inline'
    end
  end
end
