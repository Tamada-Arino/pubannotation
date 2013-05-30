# encoding: UTF-8
require 'pmcdoc'
require 'utfrewrite'
require 'aligner'

class ApplicationController < ActionController::Base
  protect_from_forgery
  after_filter :store_location

  def store_location
    if request.fullpath != new_user_session_path && request.fullpath != new_user_registration_path && request.method == 'GET'
      session[:after_sign_in_path] = request.fullpath
    end
  end
  
  def after_sign_in_path_for(resource)
    session[:after_sign_in_path] ||= root_path
  end

  def after_sign_out_path_for(resource_or_scope)
    request.referrer
  end

  def get_docspec(params)
    if params[:pmdoc_id]
      sourcedb = 'PubMed'
      sourceid = params[:pmdoc_id]
      serial   = 0
    elsif params[:pmcdoc_id]
      sourcedb = 'PMC'
      sourceid = params[:pmcdoc_id]
      serial   = params[:div_id]
    else
      sourcedb = nil
      sourceid = nil
      serial   = nil
    end

    return sourcedb, sourceid, serial
  end


  def get_project (project_name)
    project = Project.find_by_name(project_name)
    if project
      if (project.accessibility == 1 or (user_signed_in? and project.user == current_user))
        return project, nil
      else
        return nil, "The annotation set, #{project_name}, is specified as private."
      end
    else
      return nil, "The annotation set, #{project_name}, does not exist."
    end
  end


  def get_projects (doc = nil)
    projects = (doc)? doc.projects : Project.all
    projects.sort!{|x, y| x.name <=> y.name}
    projects = projects.keep_if{|a| a.accessibility == 1 or (user_signed_in? and a.user == current_user)}
  end


  def get_doc (sourcedb, sourceid, serial = 0, project = nil)
    doc = Doc.find_by_sourcedb_and_sourceid_and_serial(sourcedb, sourceid, serial)
    if doc
      if project and !doc.projects.include?(project)
        doc = nil
        notice = "The document, #{sourcedb}:#{sourceid}, does not belong to the annotation set, #{project.name}."
      end
    else
      notice = "No annotation to the document, #{sourcedb}:#{sourceid}, exists in PubAnnotation." 
    end

    return doc, notice
  end


  def get_divs (sourceid, project = nil)
    divs = Doc.find_all_by_sourcedb_and_sourceid('PMC', sourceid)
    if divs and !divs.empty?
      if project and !divs.first.projects.include?(project)
        divs = nil
        notice = "The document, PMC::#{sourceid}, does not belong to the annotation set, #{project.name}."
      end
    else
      divs = nil
      notice = "No annotation to the document, PMC:#{sourceid}, exists in PubAnnotation." 
    end

    return [divs, notice]
  end


  def rewrite_ascii (docs)
    docs.each do |doc|
      doc.body = get_ascii_text(doc.body)
    end
    docs
  end


  ## get a pmdoc from pubmed
  def gen_pmdoc (pmid)
    RestClient.get "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&id=#{pmid}" do |response, request, result|
      case response.code
      when 200
        parser   = XML::Parser.string(response, :encoding => XML::Encoding::UTF_8)
        doc      = parser.parse
        result   = doc.find_first('/PubmedArticleSet').content.strip
        return nil if result.empty?
        title    = doc.find_first('/PubmedArticleSet/PubmedArticle/MedlineCitation/Article/ArticleTitle')
        abstract = doc.find_first('/PubmedArticleSet/PubmedArticle/MedlineCitation/Article/Abstract/AbstractText')
        doc      = Doc.new
        doc.body = ""
        doc.body += title.content.strip if title
        doc.body += "\n" + abstract.content.strip if abstract
        doc.source = 'http://www.ncbi.nlm.nih.gov/pubmed/' + pmid
        doc.sourcedb = 'PubMed'
        doc.sourceid = pmid
        doc.serial = 0
        doc.section = 'TIAB'
        doc.save
        return doc
      else
        return nil
      end
    end
  end


  ## get a pmcdoc from pubmed central
  def gen_pmcdoc (pmcid)
    pmcdoc = PMCDoc.new(pmcid)

    if pmcdoc.doc
      divs = pmcdoc.get_divs
      if divs
        docs = []
        divs.each_with_index do |div, i|
          doc = Doc.new
          doc.body = div[1]
          doc.source = 'http://www.ncbi.nlm.nih.gov/pmc/' + pmcid
          doc.sourcedb = 'PMC'
          doc.sourceid = pmcid
          doc.serial = i
          doc.section = div[0]
          doc.save
          docs << doc
        end
        return [docs, nil]
      else
        return [nil, "no body in the document."]
      end
    else
      return [nil, pmcdoc.message]
    end
  end


  def archive_texts (docs)
    unless docs.empty?
      file_name = "docs.zip"
      t = Tempfile.new("my-temp-filename-#{Time.now}")
      Zip::ZipOutputStream.open(t.path) do |z|
        docs.each do |doc|
          # title = "#{doc.sourcedb}-#{doc.sourceid}-%02d-#{doc.section}" % doc.serial
          title = "%s-%s-%02d-%s" % [doc.sourcedb, doc.sourceid, doc.serial, doc.section]
          title.sub!(/\.$/, '')
          title.gsub!(' ', '_')
          title += ".txt" unless title.end_with?(".txt")
          z.put_next_entry(title)
          z.print doc.body
        end
      end
      send_file t.path, :type => 'application/zip',
                             :disposition => 'attachment',
                             :filename => file_name
      t.close
    end
  end


  def archive_annotation (project_name, format = 'json')
    project = Project.find_by_name(project_name)
    project.docs.each do |d|
    end
  end


  def get_conversion (annotation, converter, identifier = nil)
    RestClient.post converter, {:annotation => annotation.to_json}, :content_type => :json, :accept => :json do |response, request, result|
      case response.code
      when 200
        response
      else
        nil
      end
    end
  end


  def gen_annotations (annotation, annserver, identifier = nil)
    RestClient.post annserver, {:annotation => annotation.to_json}, :content_type => :json, :accept => :json do |response, request, result|
      case response.code
      when 200
        annotations = JSON.parse response, :symbolize_names => true
      else
        nil
      end
    end
  end


  def get_annotations (project, doc, options = {})
    if project and doc
      denotations = doc.denotations.where("project_id = ?", project.id).order('begin ASC')
      hdenotations = denotations.collect {|ca| ca.get_hash} unless denotations.empty?

      instances = doc.instances.where("instances.project_id = ?", project.id)
      instances.sort! {|i1, i2| i1.hid[1..-1].to_i <=> i2.hid[1..-1].to_i}
      hinstances = instances.collect {|ia| ia.get_hash} unless instances.empty?

      relations  = doc.subcatrels.where("relations.project_id = ?", project.id)
      relations += doc.subinsrels.where("relations.project_id = ?", project.id)
      relations.sort! {|r1, r2| r1.hid[1..-1].to_i <=> r2.hid[1..-1].to_i}
      hrelations = relations.collect {|ra| ra.get_hash} unless relations.empty?

      modifications = doc.insmods.where("modifications.project_id = ?", project.id)
      modifications += doc.subcatrelmods.where("modifications.project_id = ?", project.id)
      modifications += doc.subinsrelmods.where("modifications.project_id = ?", project.id)
      modifications.sort! {|m1, m2| m1.hid[1..-1].to_i <=> m2.hid[1..-1].to_i}
      hmodifications = modifications.collect {|ma| ma.get_hash} unless modifications.empty?

      text = doc.body
      if (options[:encoding] == 'ascii')
        asciitext = get_ascii_text (text)
        aligner = Aligner.new(text, asciitext, [["Δ", "delta"], [" ", " "], ["−", "-"], ["–", "-"], ["′", "'"], ["’", "'"]])
        # aligner = Aligner.new(text, asciitext)
        hdenotations = aligner.transform_denotations(hdenotations)
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
      annotations[:source_db] = doc.sourcedb
      annotations[:source_id] = doc.sourceid
      annotations[:division_id] = doc.serial
      annotations[:section] = doc.section
      annotations[:text] = text
      annotations[:denotations] = hdenotations if hdenotations
      annotations[:instances] = hinstances if hinstances
      annotations[:relations] = hrelations if hrelations
      annotations[:modifications] = hmodifications if hmodifications
      annotations
    else
      nil
    end
  end


  def save_annotations (annotations, project, doc)
    denotations, notice = clean_hdenotations(annotations[:denotations])
    if denotations
      denotations = realign_denotations(denotations, annotations[:text], doc.body)

      if denotations
        denotations_old = doc.denotations.where("project_id = ?", project.id)
        denotations_old.destroy_all
      
        save_hdenotations(denotations, project, doc)

        if annotations[:instances] and !annotations[:instances].empty?
          instances = annotations[:instances]
          instances = instances.values if instances.respond_to?(:values)
          save_hinstances(instances, project, doc)
        end

        if annotations[:relations] and !annotations[:relations].empty?
          relations = annotations[:relations]
          relations = relations.values if relations.respond_to?(:values)
          save_hrelations(relations, project, doc)
        end

        if annotations[:modifications] and !annotations[:modifications].empty?
          modifications = annotations[:modifications]
          modifications = modifications.values if modifications.respond_to?(:values)
          save_hmodifications(modifications, project, doc)
        end

        notice = 'Annotations were successfully created/updated.'
      end
    end

    notice
  end


  ## get denotations
  def get_denotations (project_name, sourcedb, sourceid, serial = 0)
    denotations = []

    if sourcedb and sourceid and doc = Doc.find_by_sourcedb_and_sourceid_and_serial(sourcedb, sourceid, serial)
      if project_name and project = doc.projects.find_by_name(project_name)
        denotations = doc.denotations.where("project_id = ?", project.id).order('begin ASC')
      else
        denotations = doc.denotations
      end
    else
      if project_name and project = Project.find_by_name(project_name)
        denotations = project.denotations
      else
        denotations = Denotation.all
      end
    end

    denotations
  end


  # get denotations (hash version)
  def get_hdenotations (project_name, sourcedb, sourceid, serial = 0)
    denotations = get_denotations(project_name, sourcedb, sourceid, serial)
    hdenotations = denotations.collect {|ca| ca.get_hash}
    hdenotations
  end


  def clean_hdenotations (denotations)
    denotations = denotations.values if denotations.respond_to?(:values)
    ids = denotations.collect {|a| a[:id] or a["id"]}
    ids.compact!

    idnum = 1
    denotations.each do |a|
      return nil, "format error" unless (a[:denotation] or (a[:begin] and a[:end])) and a[:obj]

      unless a[:id]
        idnum += 1 until !ids.include?('T' + idnum.to_s)
        a[:id] = 'T' + idnum.to_s
        idnum += 1
      end

      if a[:denotation]
        a[:denotation][:begin] = a[:denotation][:begin].to_i
        a[:denotation][:end]   = a[:denotation][:end].to_i
      else
        a[:denotation] = Hash.new
        a[:denotation][:begin] = a.delete(:begin).to_i
        a[:denotation][:end]   = a.delete(:end).to_i
      end
    end

    [denotations, nil]
  end


  def save_hdenotations (hdenotations, project, doc)
    hdenotations.each do |a|
      ca           = Denotation.new
      ca.hid       = a[:id]
      ca.begin     = a[:denotation][:begin]
      ca.end       = a[:denotation][:end]
      ca.obj  = a[:obj]
      ca.project_id = project.id
      ca.doc_id    = doc.id
      ca.save
    end
  end


  def chain_denotations (denotations_s)
    # This method is not called anywhere.
    # And just returns denotations_s array.
    mid = 0
    denotations_s.each do |ca|
      if (cid = ca.hid[1..-1].to_i) > mid 
        mid = cid
      end
    end
  end


  def bag_denotations (denotations, relations)
    tomerge = Hash.new

    new_relations = Array.new
    relations.each do |ra|
      if ra[:type] == 'lexChain'
        tomerge[ra[:object]] = ra[:subject]
      else
        new_relations << ra
      end
    end
    idx = Hash.new
    denotations.each_with_index {|ca, i| idx[ca[:id]] = i}

    mergedto = Hash.new
    tomerge.each do |from, to|
      to = mergedto[to] if mergedto.has_key?(to)
      p idx[from]
      fca = denotations[idx[from]]
      tca = denotations[idx[to]]
      tca[:denotation] = [tca[:denotation]] unless tca[:denotation].respond_to?('push')
      tca[:denotation].push (fca[:denotation])
      denotations.delete_at(idx[from])
      mergedto[from] = to
    end

    return denotations, new_relations
  end


  ## get instances
  def get_instances (project_name, sourcedb, sourceid, serial = 0)
    instances = []

    if sourcedb and sourceid and doc = Doc.find_by_sourcedb_and_sourceid_and_serial(sourcedb, sourceid, serial)
      if project_name and project = doc.projects.find_by_name(project_name)
        instances = doc.instances.where("instances.project_id = ?", project.id)
        instances.sort! {|i1, i2| i1.hid[1..-1].to_i <=> i2.hid[1..-1].to_i}
      else
        instances = doc.instances
      end
    else
      if project_name and project = Project.find_by_name(project_name)
        instances = project.instances
      else
        instances = Instance.all
      end
    end

    instances
  end


  # get instances (hash version)
  def get_hinstances (project_name, sourcedb, sourceid, serial = 0)
    instances = get_instances(project_name, sourcedb, sourceid, serial)
    hinstances = instances.collect {|ia| ia.get_hash}
  end


  def save_hinstances (hinstances, project, doc)
    hinstances.each do |a|
      ia           = Instance.new
      ia.hid       = a[:id]
      ia.pred   = a[:type]
      ia.obj    = Denotation.find_by_doc_id_and_project_id_and_hid(doc.id, project.id, a[:object])
      ia.project_id = project.id
      ia.save
    end
  end


  ## get relations
  def get_relations (project_name, sourcedb, sourceid, serial = 0)
    relations = []

    if sourcedb and sourceid and doc = Doc.find_by_sourcedb_and_sourceid_and_serial(sourcedb, sourceid, serial)
      if project_name and project = doc.projects.find_by_name(project_name)
        relations  = doc.subcatrels.where("relations.project_id = ?", project.id)
        relations += doc.subinsrels.where("relations.project_id = ?", project.id)
        relations.sort! {|r1, r2| r1.hid[1..-1].to_i <=> r2.hid[1..-1].to_i}
#        relations += doc.objcatrels.where("relations.project_id = ?", project.id)
#        relations += doc.objinsrels.where("relations.project_id = ?", project.id)
      else
        relations = doc.subcatrels + doc.subinsrels unless doc.denotations.empty?
      end
    else
      if project_name and project = Project.find_by_name(project_name)
        relations = project.relations
      else
        relations = Relation.all
      end
    end

    relations
  end


  # get relations (hash version)
  def get_hrelations (project_name, sourcedb, sourceid, serial = 0)
    relations = get_relations(project_name, sourcedb, sourceid, serial)
    hrelations = relations.collect {|ra| ra.get_hash}
  end


  def save_hrelations (hrelations, project, doc)
    hrelations.each do |a|
      ra           = Relation.new
      ra.hid       = a[:id]
      ra.pred   = a[:type]
      ra.subj    = case a[:subject]
        when /^T/ then Denotation.find_by_doc_id_and_project_id_and_hid(doc.id, project.id, a[:subject])
        else           doc.instances.find_by_project_id_and_hid(project.id, a[:subject])
      end
      ra.obj    = case a[:object]
        when /^T/ then Denotation.find_by_doc_id_and_project_id_and_hid(doc.id, project.id, a[:object])
        else           doc.instances.find_by_project_id_and_hid(project.id, a[:object])
      end
      ra.project_id = project.id
      ra.save
    end
  end


  ## get modifications
  def get_modifications (project_name, sourcedb, sourceid, serial = 0)
    modifications = []

    if sourcedb and sourceid and doc = Doc.find_by_sourcedb_and_sourceid_and_serial(sourcedb, sourceid, serial)
      if project_name and project = doc.projects.find_by_name(project_name)
        modifications = doc.insmods.where("modifications.project_id = ?", project.id)
        modifications += doc.subcatrelmods.where("modifications.project_id = ?", project.id)
        modifications += doc.subinsrelmods.where("modifications.project_id = ?", project.id)
        modifications.sort! {|m1, m2| m1.hid[1..-1].to_i <=> m2.hid[1..-1].to_i}
      else
        #modifications = doc.modifications unless doc.denotations.empty?
        modifications = doc.insmods
        modifications += doc.subcatrelmods
        modifications += doc.subinsrelmods
        modifications.sort! {|m1, m2| m1.hid[1..-1].to_i <=> m2.hid[1..-1].to_i}
      end
    else
      if project_name and project = Project.find_by_name(project_name)
        modifications = project.modifications
      else
        modifications = Modification.all
      end
    end

    modifications
  end


  # get modifications (hash version)
  def get_hmodifications (project_name, sourcedb, sourceid, serial = 0)
    modifications = get_modifications(project_name, sourcedb, sourceid, serial)
    hmodifications = modifications.collect {|ma| ma.get_hash}
  end


  def save_hmodifications (hmodifications, project, doc)
    hmodifications.each do |a|
      ma           = Modification.new
      ma.hid       = a[:id]
      ma.pred   = a[:type]
      ma.obj    = case a[:object]
        when /^R/
          #doc.subcatrels.find_by_project_id_and_hid(project.id, a[:object])
          doc.subinsrels.find_by_project_id_and_hid(project.id, a[:object])
        else
          doc.instances.find_by_project_id_and_hid(project.id, a[:object])
      end
      ma.project_id = project.id
      ma.save
    end
  end


  def get_ascii_text(text)
    rewritetext = Utfrewrite.utf8_to_ascii(text)
    #rewritetext = text

    # escape non-ascii characters
    coder = HTMLEntities.new
    asciitext = coder.encode(rewritetext, :named)
    # restore back
    # greek letters
    asciitext.gsub!(/&[Aa]lpha;/, "alpha")
    asciitext.gsub!(/&[Bb]eta;/, "beta")
    asciitext.gsub!(/&[Gg]amma;/, "gamma")
    asciitext.gsub!(/&[Dd]elta;/, "delta")
    asciitext.gsub!(/&[Ee]psilon;/, "epsilon")
    asciitext.gsub!(/&[Zz]eta;/, "zeta")
    asciitext.gsub!(/&[Ee]ta;/, "eta")
    asciitext.gsub!(/&[Tt]heta;/, "theta")
    asciitext.gsub!(/&[Ii]ota;/, "iota")
    asciitext.gsub!(/&[Kk]appa;/, "kappa")
    asciitext.gsub!(/&[Ll]ambda;/, "lambda")
    asciitext.gsub!(/&[Mm]u;/, "mu")
    asciitext.gsub!(/&[Nn]u;/, "nu")
    asciitext.gsub!(/&[Xx]i;/, "xi")
    asciitext.gsub!(/&[Oo]micron;/, "omicron")
    asciitext.gsub!(/&[Pp]i;/, "pi")
    asciitext.gsub!(/&[Rr]ho;/, "rho")
    asciitext.gsub!(/&[Ss]igma;/, "sigma")
    asciitext.gsub!(/&[Tt]au;/, "tau")
    asciitext.gsub!(/&[Uu]psilon;/, "upsilon")
    asciitext.gsub!(/&[Pp]hi;/, "phi")
    asciitext.gsub!(/&[Cc]hi;/, "chi")
    asciitext.gsub!(/&[Pp]si;/, "psi")
    asciitext.gsub!(/&[Oo]mega;/, "omega")

    # symbols
    asciitext.gsub!(/&apos;/, "'")
    asciitext.gsub!(/&lt;/, "<")
    asciitext.gsub!(/&gt;/, ">")
    asciitext.gsub!(/&quot;/, '"')
    asciitext.gsub!(/&trade;/, '(TM)')
    asciitext.gsub!(/&rarr;/, ' to ')
    asciitext.gsub!(/&hellip;/, '...')

    # change escape characters
    asciitext.gsub!(/&([a-zA-Z]{1,10});/, '==\1==')
    asciitext.gsub!('==amp==', '&')

    asciitext
  end


  # to work on the hash representation of denotations
  # to assume that there is no bag representation to this method
  def realign_denotations (denotations, from_text, to_text)
    return nil if denotations == nil

    position_map = Hash.new
    numchar, numdiff, diff = 0, 0, 0

    Diff::LCS.sdiff(from_text, to_text) do |h|
      position_map[h.old_position] = h.new_position
      numchar += 1
      if (h.new_position - h.old_position) != diff
        numdiff +=1
        diff = h.new_position - h.old_position
      end
    end
    last = from_text.length
    position_map[last] = position_map[last - 1] + 1

    # TODO
    # if (numdiff.to_f / numchar) > 2
    #   return nil, "The text is too much different from PubMed. The mapping could not be calculated.: #{numdiff}/#{numchar}"
    # else

    denotations_new = Array.new(denotations)

    (0...denotations.length).each do |i|
      denotations_new[i][:denotation][:begin] = position_map[denotations[i][:denotation][:begin]]
      denotations_new[i][:denotation][:end]   = position_map[denotations[i][:denotation][:end]]
    end

    denotations_new
  end

  def adjust_denotations (denotations, text)
    return nil if denotations == nil

    delimiter_characters = [
          " ",
          ".",
          "!",
          "?",
          ",",
          ":",
          ";",
          "+",
          "-",
          "/",
          "&",
          "(",
          ")",
          "{",
          "}",
          "[",
          "]",
          "\\",
          "\"",
          "'",
          "\n"
      ]

    denotations_new = Array.new(denotations)

    denotations_new.each do |c|
      while c[:denotation][:begin] > 0 and !delimiter_characters.include?(text[c[:denotation][:begin] - 1])
        c[:denotation][:begin] -= 1
      end

      while c[:denotation][:end] < text.length and !delimiter_characters.include?(text[c[:denotation][:end]])
        c[:denotation][:end] += 1
      end
    end

    denotations_new
  end


  def get_navigator ()
    navigator = []
    path = ''
    parts = request.fullpath.split('/')
    parts.each do |p|
      path += '/' + p
      navigator.push([p, path]);
    end
    navigator
  end

end