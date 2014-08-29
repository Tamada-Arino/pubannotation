require 'text_alignment'

module AnnotationsHelper
  def get_annotations (project, doc, options = {})
    if doc.present?
      hdenotations = doc.hdenotations(project, options)
      hrelations = doc.hrelations(project, options)
      hmodifications = doc.hmodifications(project, options)
      text = doc.body
      if (options[:encoding] == 'ascii')
        asciitext = get_ascii_text (text)
        text_alignment = TextAlignment::TextAlignment.new(text, asciitext)
        hdenotations = text_alignment.transform_denotations(hdenotations)
        # hdenotations = adjust_denotations(hdenotations, asciitext)
        text = asciitext
      end

      if (options[:discontinuous_annotation] == 'bag')
        # TODO: convert to hash representation
        hdenotations, hrelations = bag_denotations(hdenotations, hrelations)
      end

      annotations = Hash.new
      # if doc.sourcedb == 'PudMed'
      #   annotations[:pmdoc_id] = doc.sourceid
      # elsif doc.sourcedb == 'PMC'
      #   annotations[:pmcdoc_id] = doc.sourceid
      #   annotations[:div_id] = doc.serial
      # end
      
      # project
      if project.present?
        annotations[:project] = project[:name]
      end 
      # doc
      annotations[:source_db] = doc.sourcedb
      annotations[:source_id] = doc.sourceid
      annotations[:division_id] = doc.serial
      annotations[:section] = doc.section
      annotations[:text] = text
      # doc.relational_models
      annotations[:denotations] = hdenotations if hdenotations
      annotations[:relations] = hrelations if hrelations
      annotations[:modifications] = hmodifications if hmodifications
      annotations
    else
      nil
    end
  end

  def get_focus(options)
    if options.present? && options[:params].present? && options[:params][:begin].present?
      context_size_value = options[:params][:context_size].to_i
      end_value = options[:params][:end].to_i - options[:params][:begin].to_i + context_size_value
      begin_value = 0 + context_size_value
      {begin: begin_value, end: end_value}
    end
  end

  def get_annotations_for_json(project, doc, options = {})
    if doc.present?
      text = doc.body
      annotations = Hash.new
      if doc.has_divs?
        annotations[:target] = Rails.application.routes.url_helpers.doc_sourcedb_sourceid_divs_show_path(doc.sourcedb, doc.sourceid, doc.serial, :only_path => false)
      else
        annotations[:target] = Rails.application.routes.url_helpers.doc_sourcedb_sourceid_show_path(doc.sourcedb, doc.sourceid, :only_path => false)
      end
      if (options[:encoding] == 'ascii')
        asciitext = get_ascii_text(text)
        annotations[:text] = asciitext
      else
        annotations[:text] = text
      end
      # project
      if project.present?
        get_annotation_relational_models(doc, project, text, asciitext, annotations, options)
      elsif doc.projects.present?
        annotations[:tracks] = Array.new
        i = 0
        project_names = options[:projects].split(',') if options[:projects].present?
        doc.projects.name_in(project_names).each do |project|
          annotations[:tracks][i] = Hash.new
          get_annotation_relational_models(doc, project, text, asciitext, annotations[:tracks][i], options)
          i += 1
        end
      end

      if options[:doc_spans].present?
        if annotations[:tracks].present?
          annotations[:tracks].each do |track|
            if track[:denotations].present?
              track[:denotations] = set_denotations_begin_end(track[:denotations], options)
            end
          end
        elsif annotations[:denotations].present?
          annotations[:denotations] = set_denotations_begin_end(annotations[:denotations], options)
        end
      end
      
      focus = get_focus(options)
      if focus.present?
        annotations[:focus] = focus
      end
      annotations
    else
      nil
    end
  end

  def set_denotations_begin_end(denotations, options)
    denotations.each do |d|
      d[:span][:begin] -= options[:params][:begin].to_i
      d[:span][:end]   -= options[:params][:begin].to_i
      if options[:params][:context_size].present?
        d[:span][:begin] += options[:params][:context_size].to_i
        d[:span][:end] += options[:params][:context_size].to_i
      end
    end
    return denotations
  end
  
  def get_annotation_relational_models(doc, project, text, asciitext, annotations, options)
    annotations[:project] = Rails.application.routes.url_helpers.project_path(project.name, :only_path => false)
    hrelations = doc.hrelations(project, options)
    hmodifications = doc.hmodifications(project, options)
    hdenotations = doc.hdenotations(project, options)
    if options[:encoding] == 'ascii'
      text_alignment = TextAlignment::TextAlignment.new(text, asciitext)
      hdenotations = text_alignment.transform_denotations(hdenotations)
    end
    if options[:discontinuous_annotation] == 'bag'
      hdenotations, hrelations = bag_denotations(hdenotations, hrelations)
    end
    # doc.relational_models
    annotations[:denotations] = hdenotations if hdenotations
    annotations[:relations] = hrelations if hrelations
    annotations[:modifications] = hmodifications if hmodifications
    annotations
  end
  
  def bag_denotations (denotations, relations)
    tomerge = Hash.new

    new_relations = Array.new
    relations.each do |ra|
      if ra[:pred] == '_lexChain'
        tomerge[ra[:obj]] = ra[:subj]
      else
        new_relations << ra
      end
    end
    idx = Hash.new
    denotations.each_with_index {|ca, i| idx[ca[:id]] = i}

    mergedto = Hash.new
    tomerge.each do |from, to|
      to = mergedto[to] if mergedto.has_key?(to)
      fca = denotations[idx[from]]
      tca = denotations[idx[to]]
      tca[:span] = [tca[:span]] unless tca[:span].respond_to?('push')
      tca[:span].push (fca[:span])
      denotations.delete_at(idx[from])
      mergedto[from] = to
    end

    return denotations, new_relations
  end
  
  def project_annotations_zip_link_helper(project)
    if project.annotations_zip_downloadable == true
      file_path = project.annotations_zip_path
      
      if File.exist?(file_path) == true
        zip_created_at = File.ctime(file_path)
        # when ZIP file exists 
        html = link_to "#{project.name}.zip", "/annotations/#{project.name}.zip", :class => 'button'
        html += content_tag :span, "#{zip_created_at.strftime("#{t('controllers.shared.last_modified_at')}:%Y-%m-%d %T")}", :class => 'zip_time_stamp'
        if zip_created_at < project.annotations_updated_at
          html += link_to t('controllers.annotations.update_zip'), project_annotations_path(project.name, :delay => true, :update => true), :class => 'button', :style => "margin-left: 0.5em", :confirm => t('controllers.annotations.confirm_create_zip')
        end
        html
      else
        # when ZIP file deos not exists 
        delayed_job_tasks = ActiveRecord::Base.connection.execute('SELECT * FROM delayed_jobs').select{|delayed_job| delayed_job['handler'].include?(project.name) && delayed_job['handler'].include?('save_annotation_zip')}
        if delayed_job_tasks.blank?
          # when delayed_job exists
          link_to t('controllers.annotations.create_zip'), project_annotations_path(project.name, :delay => true), :class => 'button', :confirm => t('controllers.annotations.confirm_create_zip')
        else
          # delayed_job does not exists
          t('views.shared.zip.delayed_job_present')
        end
      end    
    end    
  end

  def annotations_destroy_all_helper(doc, project)
    # TODO should be instance method
    if doc
      annotations = doc.denotations.where("project_id = ?", project.id)
      
      ActiveRecord::Base.transaction do
        begin
          annotations.destroy_all
        rescue => e
          flash[:notice] = e
        end
      end
    end
  end
  
  def annotations_url_helper
    if params[:div_id].present?
      if params[:action] == 'spans'
        spans_annotations_project_sourcedb_sourceid_divs_docs_url(@project.name, @doc.sourcedb, @doc.sourceid, @doc.serial, params[:begin], params[:end])
      else
        annotations_project_sourcedb_sourceid_divs_docs_url(@project.name, @doc.sourcedb, @doc.sourceid, @doc.serial)
      end      
    else
      if params[:action] == 'spans'
        spans_annotations_project_sourcedb_sourceid_docs_url(@project.name, @doc.sourcedb, @doc.sourceid, params[:begin], params[:end])
      else
        annotations_project_sourcedb_sourceid_docs_url(@project.name, @doc.sourcedb, @doc.sourceid)
      end
    end
  end  

  def annotations_form_action_helper
    if params[:id].present?
      annotations_project_doc_path(@project.name, @doc.id)
    else
      if params[:div_id].present?
        generate_annotatons_project_sourcedb_sourceid_divs_docs_path(@project.name, @doc.sourcedb, @doc.sourceid, @doc.serial)
      else
        generate_annotatons_project_sourcedb_sourceid_docs_path(@project.name, @doc.sourcedb, @doc.sourceid)
      end
    end
  end

  def get_doc_info (doc_uri)
    source_db = (doc_uri =~ %r|/sourcedb/([^/]+)|)? $1 : nil
    source_id = (doc_uri =~ %r|/sourceid/([^/]+)|)? $1 : nil
    div_id    = (doc_uri =~ %r|/divs/([^/]+)|)? $1 : nil
    if div_id.present?
      doc = Doc.find_by_sourcedb_and_sourceid_and_serial(source_db, source_id, div_id.to_i)
      section   = doc.section.to_s if doc.present?
    end
    docinfo   = (div_id == nil)? "#{source_db}-#{source_id}" : "#{source_db}-#{source_id}-#{div_id}-#{section}"
  end
end
