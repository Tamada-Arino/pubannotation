class ObtainAnnotationsWithCallbackJob < ApplicationJob
  include UseJobRecordConcern
  include ActionView::Helpers::NumberHelper

  queue_as :low_priority

  def perform(project, filepath, annotator, options)
    line_count = File.read(filepath).each_line.count

    prepare_progress_record(line_count)

    # for asynchronous protocol
    max_text_size = annotator.max_text_size || (annotator.async_protocol ? Annotator::MaxTextAsync : Annotator::MaxTextSync)
    single_doc_processing_p = annotator.single_doc_processing?

    docs = []
    docs_size = 0
    File.foreach(filepath) do |line|
      docid = line.chomp.strip
      doc = Doc.find(docid)
      doc.set_ascii_body if options[:encoding] == 'ascii'
      doc_length = doc.body.length

      if docs.present? && (single_doc_processing_p || (docs_size + doc_length) > max_text_size)
        begin
          handle_annotate_request(annotator, project, docs, options, max_text_size)
        rescue Exceptions::JobSuspendError
          raise
        rescue => e
          if docs.length < 10
            docs.each do |doc|
              @job.add_message sourcedb: doc.sourcedb,
                               sourceid: doc.sourceid,
                               body: "Could not obtain annotations: #{exception_message(e)}"
            end
          else
            @job.add_message body: "Could not obtain annotations for #{docs.length} docs: #{exception_message(e)}"
          end
        ensure
          docs.clear
          docs_size = 0
        end
      end

      docs << doc
      docs_size += doc_length

    rescue Exceptions::JobSuspendError
      raise
    rescue RuntimeError => e
      if docs.length < 10
        docs.each do |doc|
          @job.add_message sourcedb: doc.sourcedb,
                           sourceid: doc.sourceid,
                           body: "Runtime error: #{exception_message(e)}"
        end
      else
        @job.add_message body: "Runtime error while processing #{docs.length} docs: #{exception_message(e)}"
      end
    end

    if docs.present?
      handle_annotate_request(annotator, project, docs, options, max_text_size)
    end

    File.unlink(filepath)
  end

  def job_name
    "Obtain annotations: #{resource_name}"
  end

private

  def handle_annotate_request(annotator, project, docs, options, max_text_size)
    if docs.length == 1 && docs.first.body.length > max_text_size
      slice_large_document(project, docs.first, annotator, options, max_text_size)
    else
      hdocs = docs.map{|d| d.hdoc}
      make_request(project, docs, hdocs, annotator, options)
    end
  end

  def slice_large_document(project, doc, annotator, options, max_text_size)
    slices = doc.get_slices(max_text_size)
    count = @job.num_items + slices.length - 1
    @job.update_attribute(:num_items, count)
    if slices.length > 1
      @job.add_message sourcedb:doc.sourcedb,
                       sourceid:doc.sourceid,
                       body: "The document was too big to be processed at once (#{number_with_delimiter(doc.body.length)} > #{number_with_delimiter(max_text_size)}). For proceding, it was divided into #{slices.length} slices."
    end

    # delete all the annotations here for a better performance
    project.delete_doc_annotations(doc) if options[:mode] == 'replace'
    slices.each do |slice|
      hdoc = [{text:doc.get_text(options[:span]), sourcedb:doc.sourcedb, sourceid:doc.sourceid}]
      make_request(project, doc, hdoc, annotator, options.merge(span:slice))
    rescue Exceptions::JobSuspendError
      raise
    rescue RuntimeError => e
      @job.add_message sourcedb:doc.sourcedb,
                       sourceid:doc.sourceid,
                       body: "Could not obtain for the slice (#{slice[:begin]}, #{slice[:end]}): #{exception_message(e)}"
    rescue => e
      @job.add_message sourcedb:doc.sourcedb,
                       sourceid:doc.sourceid,
                       body: "Error while processing the slice (#{slice[:begin]}, #{slice[:end]}): #{exception_message(e)}"
    end
  end

  def make_request(project, docs, hdocs, annotator, options)
    uuid = SecureRandom.uuid
    AnnotationReception.create!(annotator_id: annotator.id, project_id: project.id, uuid:, options:)
    method, url, params, payload = annotator.prepare_request(hdocs)
    payload[:callback_url] = "#{Rails.application.config.host_url}/annotation_reception/#{uuid}"

    annotator.make_request(method, url, params, payload)
  end

  def exception_message(exception)
    exception.message
  rescue => e
    "exception message inaccessible:\n#{exception}:\n#{exception.backtrace.join("\n")}"
  end

  def resource_name
    self.arguments[2].name
  end
end
