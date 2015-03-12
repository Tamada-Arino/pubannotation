require 'text_alignment'

module AnnotationsHelper
  def annotations_count_helper(project, doc = nil, span = nil)
    span = {begin: params[:begin], end: params[:end]} if params[:begin] && params[:end]
    if doc.present?
      doc.annotations_count(project, span)
    else
      project.annotations_count
    end
  end

  def annotations_url
    "#{url_for(only_path: false)}".sub('/visualize', '').sub('/annotations', '') + '/annotations'
  end  

  def annotations_path
    "#{url_for(only_path: true)}".sub('/visualize', '').sub('/annotations', '') + '/annotations'
  end  

  def textae_url(project, source_url)
    return '' unless project.present? && source_url.present?
    connector = if project.editor.include?('?') then '&' else '?' end
    "#{project.editor}#{connector}target=#{source_url}.json"
  end

  # To be deprecated in favor of doc.get_annotations
  def get_annotations (project, doc, options = {})
    if doc.present?
      hdenotations = doc.hdenotations(project)
      hrelations = doc.hrelations(project)
      hmodifications = doc.hmodifications(project)
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
      #   annotations[:divid] = doc.serial
      # end
      
      # project
      annotations[:project] = project[:name] if project.present?

      # doc
      annotations[:sourcedb] = doc.sourcedb
      annotations[:sourceid] = doc.sourceid
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

  # normalize annotations passed by an HTTP call
  def normalize_annotations!(annotations)
    raise ArgumentError, "annotations must be a hash." unless annotations.class == Hash
    raise ArgumentError, "annotations must include a 'text'"  unless annotations[:text].present?

    if annotations[:denotations].present?
      raise ArgumentError, "'denotations' must be an array." unless annotations[:denotations].class == Array
      annotations[:denotations].each{|d| d = d.symbolize_keys}

      ids = annotations[:denotations].collect{|d| d[:id]}.compact
      idnum = 1

      annotations[:denotations].each do |a|
        raise ArgumentError, "a denotation must have a 'span' or a pair of 'begin' and 'end'." unless a[:span].present? || (a[:begin].present? && a[:end].present?)
        raise ArgumentError, "a denotation must have an 'obj'." unless a[:obj].present?

        unless a.has_key? :id
          idnum += 1 until !ids.include?('T' + idnum.to_s)
          a[:id] = 'T' + idnum.to_s
          idnum += 1
        end

        if a[:span].present?
          a[:span] = a[:span].symbolize_keys
          a[:span] = {begin: a[:span][:begin].to_i, end: a[:span][:end].to_i}
        else
          a[:span] = {begin: a[:begin].to_i, end: a[:end].to_i}
        end
      end
    end

    if annotations[:relations].present?
      raise ArgumentError, "'relations' must be an array." unless annotations[:relations].class == Array
      annotations[:relations].each{|a| a = a.symbolize_keys}

      ids = annotations[:relations].collect{|a| a[:id]}.compact
      idnum = 1

      annotations[:relations].each do |a|
        raise ArgumentError, "a relation must have 'subj', 'obj' and 'pred'." unless a[:subj].present? && a[:obj].present? && a[:pred].present?

        unless a.has_key? :id
          idnum += 1 until !ids.include?('R' + idnum.to_s)
          a[:id] = 'R' + idnum.to_s
          idnum += 1
        end
      end
    end

    if annotations[:modifications].present?
      raise ArgumentError, "'modifications' must be an array." unless annotations[:modifications].class == Array
      annotations[:modifications].each{|a| a = a.symbolize_keys} 

      ids = annotations[:modifications].collect{|a| a[:id]}.compact
      idnum = 1

      annotations[:modifications].each do |a|
        raise ArgumentError, "a modification must have 'pred' and 'obj'." unless a[:pred].present? && a[:obj].present?

        unless a.has_key? :id
          idnum += 1 until !ids.include?('M' + idnum.to_s)
          a[:id] = 'M' + idnum.to_s
          idnum += 1
        end
      end
    end

    annotations
  end

  def get_focus(options)
    if options.present? && options[:params].present? && options[:params][:begin].present? && options[:params][:context_size]
      sbeg = options[:params][:begin].to_i
      send = options[:params][:end].to_i
      context_size = options[:params][:context_size].to_i
      fbeg = (context_size < sbeg) ? context_size : sbeg
      fend = send - sbeg + fbeg
      {begin: fbeg, end: fend}
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
    hrelations = doc.hrelations(project)
    hmodifications = doc.hmodifications(project)
    hdenotations = doc.hdenotations(project)
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
      file_path = project.annotations_zip_system_path
      
      if File.exist?(file_path) == true
        zip_created_at = File.ctime(file_path)
        # when ZIP file exists 
        html = link_to "Download '#{project.annotations_zip_filename}'", project_annotations_zip_path(project.name), :class => 'button'
        html += content_tag :span, "#{zip_created_at.strftime("#{t('controllers.shared.created_at')}:%Y-%m-%d %T")}", :class => 'zip_time_stamp'
        if zip_created_at < project.annotations_updated_at
          html += link_to t('controllers.annotations.update_zip'), project_create_annotations_zip_path(project.name, :update => true), :class => 'button', :style => "margin-left: 0.5em", :confirm => t('controllers.annotations.confirm_create_zip')
        end
        if project.user == current_user
          html += link_to t('views.shared.delete'), project_delete_annotations_zip_path(project.name), confirm: t('controllers.shared.confirm_delete'), :class => 'button'
        end
        html
      else
        # when ZIP file deos not exists 
        delayed_job_tasks = ActiveRecord::Base.connection.execute('SELECT * FROM delayed_jobs').select{|delayed_job| delayed_job['handler'].include?(project.name) && delayed_job['handler'].include?('create_annotations_zip')}
        if project.user == current_user
          if delayed_job_tasks.blank?
            # when delayed_job exists
            link_to t('controllers.annotations.create_zip'), project_create_annotations_zip_path(project.name), :class => 'button', :confirm => t('controllers.annotations.confirm_create_zip')
          else
            # delayed_job does not exists
            t('views.shared.zip.delayed_job_present')
          end
        else
          t('views.shared.zip.download_not_available')
        end
      end    
    end    
  end

  def visualization_link(span = nil)
    if span.present? && (span[:end] - span[:begin] < 200)
      link_to(t('views.annotations.see_in_visualizaion'), annotations_url, class: 'button')
    else
      content_tag(:span, t('views.annotations.see_in_visualizaion'), title: t('views.annotations.visualization_link_disabled'), style: 'color: #999')
    end
  end

  def annotations_form_action_helper
    if params[:id].present?
      annotations_project_doc_path(@project.name, @doc.id)
    else
      if params[:divid].present?
        annotations_generate_project_sourcedb_sourceid_divs_docs_path(@project.name, @doc.sourcedb, @doc.sourceid, @doc.serial)
      else
        annotations_generate_project_sourcedb_sourceid_docs_path(@project.name, @doc.sourcedb, @doc.sourceid)
      end
    end
  end

  def get_doc_info (doc_uri)
    sourcedb = (doc_uri =~ %r|/sourcedb/([^/]+)|)? $1 : nil
    sourceid = (doc_uri =~ %r|/sourceid/([^/]+)|)? $1 : nil
    divid    = (doc_uri =~ %r|/divs/([^/]+)|)? $1 : nil
    if divid.present?
      doc = Doc.find_by_sourcedb_and_sourceid_and_serial(sourcedb, sourceid, divid.to_i)
      section   = doc.section.to_s if doc.present?
    end
    docinfo   = (divid == nil)? "#{sourcedb}-#{sourceid}" : "#{sourcedb}-#{sourceid}-#{divid}-#{section}"
  end
end
