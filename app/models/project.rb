class Project < ActiveRecord::Base
  include AnnotationsHelper
  DOWNLOADS_PATH = "/downloads/"

  before_validation :cleanup_namespaces
  after_validation :user_presence
  serialize :namespaces
  belongs_to :user
  has_and_belongs_to_many :docs, :after_add => [:increment_docs_counter, :update_annotations_updated_at], :after_remove => [:decrement_docs_counter, :update_annotations_updated_at]
  has_and_belongs_to_many :pmdocs, :join_table => :docs_projects, :class_name => 'Doc', :conditions => {:sourcedb => 'PubMed'}
  has_and_belongs_to_many :pmcdocs, :join_table => :docs_projects, :class_name => 'Doc', :conditions => {:sourcedb => 'PMC', :serial => 0}
  
  # Project to Proejct associations
  # parent project => associate projects = @project.associate_projects
  has_and_belongs_to_many :associate_projects, 
    :foreign_key => 'project_id', 
    :association_foreign_key => 'associate_project_id', 
    :join_table => 'associate_projects_projects',
    :class_name => 'Project', 
    :before_add => :increment_pending_associate_projects_count,
    :after_add => [:increment_counters, :copy_associate_project_relational_models],
    :after_remove => :decrement_counters
    
  # associate projects => parent projects = @project.projects
  has_and_belongs_to_many :projects, 
    :foreign_key => 'associate_project_id',
    :association_foreign_key => 'project_id',
    :join_table => 'associate_projects_projects'

  attr_accessible :name, :description, :author, :license, :status, :accessibility, :reference, :viewer, :editor, :rdfwriter, :xmlwriter, :bionlpwriter, :annotations_zip_downloadable, :namespaces, :process
  has_many :denotations, :dependent => :destroy
  has_many :relations, :dependent => :destroy
  has_many :modifications, :dependent => :destroy
  has_many :associate_maintainers, :dependent => :destroy
  has_many :associate_maintainer_users, :through => :associate_maintainers, :source => :user, :class_name => 'User'
  has_many :notices, dependent: :destroy
  validates :name, :presence => true, :length => {:minimum => 5, :maximum => 30}, uniqueness: true
  
  default_scope where(:type => nil)

  scope :accessible, -> (current_user) {
    if current_user.present?
      includes(:associate_maintainers).where('projects.accessibility = ? OR projects.user_id =? OR associate_maintainers.user_id =?', 1, current_user.id, current_user.id)
    else
      where(accessibility: 1)
    end
  }

  scope :editable, -> (current_user) {
    if current_user.present?
      includes(:associate_maintainers).where('projects.user_id =? OR associate_maintainers.user_id =?', current_user.id, current_user.id)
    else
      where(accessibility: 10)
    end
  }

  # scope for home#index
  scope :top, order('status ASC').order('denotations_count DESC').order('projects.updated_at DESC').limit(10)

  scope :not_id_in, lambda{|project_ids|
    where('projects.id NOT IN (?)', project_ids)
  }

  scope :id_in, lambda{|project_ids|
    where('projects.id IN (?)', project_ids)
  }
  
  scope :name_in, -> (project_names) {
    where('projects.name IN (?)', project_names) if project_names.present?
  }

  # scopes for order
  scope :order_pmdocs_count, 
    joins("LEFT OUTER JOIN docs_projects ON docs_projects.project_id = projects.id LEFT OUTER JOIN docs ON docs.id = docs_projects.doc_id AND docs.sourcedb = 'PubMed'").
    group('projects.id').
    order("count(docs.id) DESC")
    
  scope :order_pmcdocs_count, 
    joins("LEFT OUTER JOIN docs_projects ON docs_projects.project_id = projects.id LEFT OUTER JOIN docs ON docs.id = docs_projects.doc_id AND docs.sourcedb = 'PMC'").
    group('projects.id').
    order("count(docs.id) DESC")
    
  scope :order_denotations_count, 
    joins('LEFT OUTER JOIN denotations ON denotations.project_id = projects.id').
    group('projects.id').
    order("count(denotations.id) DESC")
    
  scope :order_relations_count,
    joins('LEFT OUTER JOIN relations ON relations.project_id = projects.id').
    group('projects.id').
    order('count(relations.id) DESC')
    
  scope :order_author,
    order('author ASC')
    
  scope :order_maintainer,
    joins('LEFT OUTER JOIN users ON users.id = projects.user_id').
    group('projects.id, users.username').
    order('users.username ASC')
  
  scope :order_association, lambda{|current_user|
    if current_user.present?
      joins("LEFT OUTER JOIN associate_maintainers ON projects.id = associate_maintainers.project_id AND associate_maintainers.user_id = #{current_user.id}").
      order("CASE WHEN projects.user_id = #{current_user.id} THEN 2 WHEN associate_maintainers.user_id = #{current_user.id} THEN 1 ELSE 0 END DESC")
    end
  }

  # default sort order priority : left > right
  DefaultSortArray = [['status', 'ASC'], ['denotations_count', 'DESC'], ['projects.updated_at', 'DESC'], ['name', 'ASC'], ['author', 'ASC'], ['users.username', 'ASC']]

  # List of column names ignore case to sort
  CaseInsensitiveArray = %w(name author users.username)

  LicenseDefault = 'Creative Commons Attribution 3.0 Unported License'
  EditorDefault = 'http://textae.pubannotation.org/editor.html?mode=edit'
  
  scope :sort_by_params, -> (sort_order) {
      sort_order = sort_order.collect{|s| s.join(' ')}.join(', ')
      unscoped.includes(:user).order(sort_order)
  }

  def status_text
   status_hash = {
     1 => I18n.t('activerecord.options.project.status.released'),
     2 => I18n.t('activerecord.options.project.status.beta'),
     3 => I18n.t('activerecord.options.project.status.developing'),
     4 => I18n.t('activerecord.options.project.status.testing')
   }

   status_hash[self.status]
  end
  
  def accessibility_text
   accessibility_hash = {
     1 => I18n.t('activerecord.options.project.accessibility.public'),
     2 => :Private
   }
   accessibility_hash[self.accessibility]
  end
  
  def process_text
   process_hash = {
     1 => I18n.t('activerecord.options.project.process.manual'),
     2 => I18n.t('activerecord.options.project.process.automatic')
   }
   process_hash[self.process]
  end

  def self.order_by(projects, order, current_user)
    case order
    when 'pmdocs_count', 'pmcdocs_count', 'denotations_count', 'relations_count'
      projects.accessible(current_user).order("#{order} DESC")
    when 'author'
      projects.accessible(current_user).order_author
    when 'maintainer'
      projects.accessible(current_user).order_maintainer
    else
      # 'association' or nil
      projects.accessible(current_user).order_association(current_user)
    end    
  end
  
  # after_add doc
  def increment_docs_counter(doc)
    if doc.sourcedb == 'PMC' && doc.serial == 0
      counter_column = :pmcdocs_count
    elsif doc.sourcedb == 'PubMed'
      counter_column = :pmdocs_count
    end
    if counter_column
      Project.increment_counter(counter_column, self.id)
      if self.projects.present?
        self.projects.each do |project|
          Project.increment_counter(counter_column, project.id)
        end          
      end
    end
  end
  
  # after_remove doc
  def decrement_docs_counter(doc)
    if doc.sourcedb == 'PMC' && doc.serial == 0
      counter_column = :pmcdocs_count
    elsif doc.sourcedb == 'PubMed'
      counter_column = :pmdocs_count
    end
    if counter_column
      Project.decrement_counter(counter_column, self.id)
      if self.projects.present?
        self.projects.each do |project|
          Project.decrement_counter(counter_column, project.id)
        end          
      end          
    end          
  end          

  def update_annotations_updated_at(doc)
    self.update_attribute(:annotations_updated_at, DateTime.now)
  end

  def associate_maintainers_addable_for?(current_user)
    if self.new_record?
      true
    else
      current_user.root? == true || current_user == self.user
    end
  end
  
  def updatable_for?(current_user)
    current_user.root? == true || (current_user == self.user || self.associate_maintainer_users.include?(current_user))
  end

  def destroyable_for?(current_user)
    current_user.root? == true || current_user == user  
  end

  def notices_destroyable_for?(current_user)
    current_user && (current_user.root? == true || current_user == user)
  end
  
  def association_for(current_user)
    if current_user.present?
      if current_user == self.user
        'M'
      elsif self.associate_maintainer_users.include?(current_user)
        'A'
      end
    end
  end
  
  def build_associate_maintainers(usernames)
    if usernames.present?
      users = User.where('username IN (?)', usernames)
      users = users.uniq if users.present?
      users.each do |user|
        self.associate_maintainers.build({:user_id => user.id})
      end
    end
  end
  
  def add_associate_projects(params_associate_projects, current_user)
    if params_associate_projects.present?
      associate_projects_names = Array.new
      params_associate_projects[:name].each do |index, name|
        associate_projects_names << name
        if params_associate_projects[:import].present? && params_associate_projects[:import][index]
          project = Project.includes(:associate_projects).find_by_name(name)
          associate_projects_accessible = project.associate_projects.accessible(current_user)
          # import associate projects which current user accessible 
          if associate_projects_accessible.present?
            associate_project_names = associate_projects_accessible.collect{|associate_project| associate_project.name}
            associate_projects_names = associate_projects_names | associate_project_names if associate_project_names.present?
          end
        end
      end
      associate_projects = Project.where('name IN (?) AND id NOT IN (?)', associate_projects_names.uniq, associate_project_and_project_ids)
      self.associate_projects << associate_projects
    end    
  end
  
  def associate_project_ids
    associate_project_ids = associate_projects.present? ? associate_projects.collect{|associate_project| associate_project.id} : []
    associate_project_ids.uniq
  end
  
  def self_id_and_associate_project_ids
    associate_project_ids << self.id if self.id.present?
  end
  
  def self_id_and_associate_project_and_project_ids
    associate_project_and_project_ids << self.id if self.id.present?
  end
  
  def project_ids
    project_ids = projects.present? ? projects.collect{|project| project.id} : []
    project_ids.uniq
  end
  
  def associate_project_and_project_ids
    if associate_project_ids.present? || project_ids.present?
      associate_project_ids | project_ids
    else
      [0]
    end
  end
  
  def associatable_project_ids(current_user)
    if self.new_record?
      associatable_projects = Project.accessible(current_user)
    else
      associatable_projects = Project.accessible(current_user).not_id_in(self.self_id_and_associate_project_and_project_ids)
    end
    associatable_projects.collect{|associatable_projects| associatable_projects.id}
  end
  
  # increment counters after add associate projects
  def increment_counters(associate_project)
    Project.update_counters self.id,
      :pmdocs_count => associate_project.pmdocs.count,
      :pmcdocs_count => associate_project.pmcdocs.count,
      :denotations_count => associate_project.denotations.count,
      :relations_count => associate_project.relations.count
  end 
  
  def increment_pending_associate_projects_count(associate_project)
    Project.increment_counter(:pending_associate_projects_count, self.id)
  end 
  
  def copy_associate_project_relational_models(associate_project)
    Project.decrement_counter(:pending_associate_projects_count, self.id)
    if associate_project.docs.present?
      copy_docs = associate_project.docs - self.docs
      copy_docs.each do |doc|
        # copy doc
        self.docs << doc
      end
    end
    
    if associate_project.denotations.present?
      # copy denotations
      associate_project.denotations.each do |denotation|
        same_denotation = self.denotations.where(
          {
            :hid => denotation.hid,
            :doc_id => denotation.doc_id,
            :begin => denotation.begin,
            :end => denotation.end,
            :obj => denotation.obj
          }
        )
        if same_denotation.blank?
          self.denotations << denotation.dup
        end
      end
    end
    
    if associate_project.relations.present?
      associate_project.relations.each do |relation|
        same_relation = self.relations.where({
          :hid => relation.hid,
          :subj_id => relation.subj_id,
          :subj_type => relation.subj_type,
          :obj_id => relation.obj_id,
          :obj_type => relation.obj_type,
          :pred => relation.pred
        })
        if same_relation.blank?
          self.relations << relation.dup
        end
      end
    end
  end
  handle_asynchronously :copy_associate_project_relational_models, :run_at => Proc.new { 1.minutes.from_now }
    
  # decrement counters after delete associate projects
  def decrement_counters(associate_project)
    Project.update_counters self.id, 
      :pmdocs_count => - associate_project.pmdocs.count,
      :pmcdocs_count => - associate_project.pmcdocs.count,
      :denotations_count => - associate_project.denotations.count,
      :relations_count => - associate_project.relations.count
  end
  
  def denotations_count(doc = nil, span = nil)
    if doc.nil?
      self.denotations.count
    else
      if span.nil?
        # begin from the doc because it should be faster.
        doc.denotations.where("denotations.project_id = ?", self.id).count
      else
        doc.hdenotations(self, span).length
      end
    end
  end

  def annotations_count(doc = nil, span = nil)
    if doc.nil?
      self.denotations.count + self.relations.count + self.modifications.count
    else
      if span.nil?
        # begin from the doc because it should be faster.
        doc.denotations.where("denotations.project_id = ?", self.id).count + doc.subcatrels.where("relations.project_id = ?", self.id).count + doc.catmods.where("modifications.project_id = ?", self.id).count + doc.subcatrelmods.where("modifications.project_id = ?", self.id).count
      else
        hdenotations = doc.hdenotations(self, span)
        ids =  hdenotations.collect{|d| d[:id]}
        hrelations = doc.hrelations(self, ids)
        ids += hrelations.collect{|d| d[:id]}
        hmodifications = doc.hmodifications(self, ids)
        hdenotations.size + hrelations.size + hmodifications.size
      end
    end
  end

  def annotations_collection(encoding = nil)
    if self.docs.present?
      self.docs.collect{|doc| doc.set_ascii_body if encoding == 'ascii'; doc.hannotations(self)}
    else
      []
    end
  end

  def json
    except_columns = %w(pmdocs_count pmcdocs_count pending_associate_projects_count user_id)
    to_json(except: except_columns, methods: :maintainer)
  end

  def docs_list_hash
    docs.collect{|doc| doc.to_list_hash} if docs.present?
  end

  def maintainer
    user.present? ? user.username : ''
  end

  def downloads_system_path
    "#{Rails.root}/public#{Project::DOWNLOADS_PATH}" 
  end

  def annotations_zip_filename
    "#{self.name.gsub(' ', '_')}-annotations.zip"
  end

  def annotations_zip_path
    "#{Project::DOWNLOADS_PATH}" + self.annotations_zip_filename
  end

  def annotations_zip_system_path
    self.downloads_system_path + self.annotations_zip_filename
  end

  def create_annotations_zip(encoding = nil)
    require 'fileutils'

    begin
      annotations_collection = self.annotations_collection(encoding)

      FileUtils.mkdir_p(self.downloads_system_path) unless Dir.exist?(self.downloads_system_path)
      file = File.new(self.annotations_zip_system_path, 'w')
      Zip::ZipOutputStream.open(file.path) do |z|
        # z.put_next_entry('project.json')
        # z.print self.json
        # z.put_next_entry('docs.json')
        # z.print self.docs_list_hash.to_json
        annotations_collection.each do |annotations|
          title = get_doc_info(annotations[:target]).sub(/\.$/, '').gsub(' ', '_')
          title += ".json" unless title.end_with?(".json")
          z.put_next_entry(title)
          z.print annotations.to_json
        end
      end
      file.close   
      self.notices.create({successful: true, method: 'create_annotations_zip'})
    # rescue => e
    #   self.notices.create({successful: false, method: 'create_annotations_zip'})
    end
  end 

  def self.params_from_json(json_file)
    project_attributes = JSON.parse(File.read(json_file))
    user = User.find_by_username(project_attributes['maintainer'])
    project_params = project_attributes.select{|key| Project.attr_accessible[:default].include?(key)}
  end

  def create_annotations_from_zip(zip_file_path, options)
    annotations_collection = Zip::ZipFile.open(zip_file_path) do |zip|
      zip.collect{|entry| JSON.parse(entry.get_input_stream.read, symbolize_names:true)}
    end

    imported, added, failed, messages = 0, 0, 0, []
    annotations_collection.each do |annotations|
      i, a, f, m = self.add_doc(annotations[:sourcedb], annotations[:sourceid])
      imported += i; added += a; failed += f
      messages << m if m.present?

      serial = annotations[:divid].present? ? annotations[:divid].to_i : 0

      doc = Doc.find_by_sourcedb_and_sourceid_and_serial(annotations[:sourcedb], annotations[:sourceid], serial)
      Shared.save_annotations(annotations, self, doc, options)
    end

    messages << "annotations loaded to #{annotations_collection.length} documents"
  end

  def save_annotations(annotations_files)
    annotations_files.each do |annotations_file|
      annotations = JSON.parse(File.read(annotations_file))
      File.unlink(annotations_file) 

      serial = annotations[:divid].present? ? annotations[:divid].to_i : 0
      doc = Doc.find_by_sourcedb_and_sourceid_and_serial(annotations[:sourcedb], annotations[:sourceid], serial)

      if doc.present?
        Shared.save_annotations(annotations, self, doc) 
      end
    end
  end

  def self.create_from_zip(zip_file, project_name, current_user)
    messages = Array.new
    errors = Array.new
    unless Dir.exist?(TempFilePath)
      FileUtils.mkdir_p(TempFilePath)
    end
    project_json_file = "#{TempFilePath}#{project_name}-project.json"
    docs_json_file = "#{TempFilePath}#{project_name}-docs.json"
    doc_annotations_files = Array.new
    # open zip file
    Zip::ZipFile.open(zip_file) do |zipfile|
      zipfile.each do |file|
        file_name = file.name
        if file_name == 'project.json'
          # extract project.json
          file.extract(project_json_file) unless File.exist?(project_json_file)
        elsif file_name == 'docs.json'
          # extract docs.json
          file.extract(docs_json_file) unless File.exist?(docs_json_file)
        else
          # extract sourcedb-sourdeid-serial-section.json
          doc_annotations_file = "#{TempFilePath}#{file.name}"
          unless File.exist?(doc_annotations_file)
            file.extract(doc_annotations_file)
            doc_annotations_files << {name: file.name, path: doc_annotations_file}
          end
        end
      end
    end

    # create project if [project_name]-project.json exist
    if File.exist?(project_json_file)
      params_from_json = Project.params_from_json(project_json_file)
      File.unlink(project_json_file)
      project_params = params_from_json
      project = Project.new(project_params)
      project.user = current_user
      if project.valid?
        project.save
        messages << I18n.t('controllers.shared.successfully_created', model: I18n.t('activerecord.models.project'))
      else
        errors << project.errors.full_messages.join('<br />')
        project = nil
      end
    end

    # create project.docs if [project_name]-docs.json exist
    if project.present?
      if File.exist?(docs_json_file)
        if project.present?
          num_created, num_added, num_failed = project.add_docs_from_json(JSON.parse(File.read(docs_json_file), :symbolize_names => true), current_user)
          messages << I18n.t('controllers.docs.create_project_docs.created_to_document_set', num_created: num_created, project_name: project.name) if num_created > 0
          messages << I18n.t('controllers.docs.create_project_docs.added_to_document_set', num_added: num_added, project_name: project.name) if num_added > 0
          messages << I18n.t('controllers.docs.create_project_docs.failed_to_document_set', num_failed: num_failed, project_name: project.name) if num_failed > 0
        end
        File.unlink(docs_json_file) 
      end

      # save annotations
      if doc_annotations_files
        delay.save_annotations(project, doc_annotations_files)
        messages << I18n.t('controllers.projects.upload_zip.delay_save_annotations')
      end
    end
    return [messages, errors]
  end

  def self.save_annotations(project, doc_annotations_files)
    doc_annotations_files.each do |doc_annotations_file|
      doc_info = doc_annotations_file[:name].split('-')
      doc = Doc.find_by_sourcedb_and_sourceid_and_serial(doc_info[0], doc_info[1], doc_info[2])
      doc_params = JSON.parse(File.read(doc_annotations_file[:path])) 
      File.unlink(doc_annotations_file[:path]) 
      if doc.present?
        if doc_params['denotations'].present?
          annotations = {
            denotations: doc_params['denotations'],
            relations: doc_params['relations'],
            text: doc_params['text']
          }
          Shared.save_annotations(annotations, project, doc)
        end
      end
    end
  end

  def add_docs_from_json(docs, user)
    num_created, num_added, num_failed = 0, 0, 0
    docs = [docs] if docs.class == Hash
    sourcedbs = docs.group_by{|doc| doc[:sourcedb]}
    if sourcedbs.present?
      sourcedbs.each do |sourcedb, docs_array|
        ids = docs_array.collect{|doc| doc[:sourceid]}.join(",")
        num_created_t, num_added_t, num_failed_t = self.add_docs({ids: ids, sourcedb: sourcedb, docs_array: docs_array, user: user})
        num_created += num_created_t
        num_added += num_added_t
        num_failed += num_failed_t
      end
    end
    return [num_created, num_added, num_failed]   
  end

  def add_docs(options = {})
    num_created, num_added, num_failed = 0, 0, 0
    ids = options[:ids].split(/[ ,"':|\t\n]+/).collect{|id| id.strip}
    ids.each do |sourceid|
      divs = Doc.find_all_by_sourcedb_and_sourceid(options[:sourcedb], sourceid)
      is_current_users_sourcedb = (options[:sourcedb] =~ /.#{Doc::UserSourcedbSeparator}#{options[:user].username}\Z/).present?
      if divs.present?
        if is_current_users_sourcedb
          # when sourcedb is user's sourcedb
          # update or create if not present
          options[:docs_array].each do |doc_array|
            # find doc sourcedb sourdeid and serial
            doc = Doc.find_or_initialize_by_sourcedb_and_sourceid_and_serial(options[:sourcedb], sourceid, doc_array['divid'])
            mappings = {
              'text' => 'body', 
              'section' => 'section', 
              'source_url' => 'source', 
              'divid' => 'serial'
            }

            doc_params = Hash[doc_array.map{|key, value| [mappings[key], value]}].select{|key| key.present?}
            if doc.new_record?
              # when same sourcedb sourceid serial not present
              doc.attributes = doc_params
              if doc.valid?
                # create
                doc.save
                self.docs << doc unless self.docs.include?(doc)
                num_created += 1
              else
                num_failed += 1
              end
            else
              # when same sourcedb sourceid serial present
              # update
              if doc.update_attributes(doc_params)
                self.docs << doc unless self.docs.include?(doc)
                num_added += 1
              else
                num_failed += 1
              end
            end
          end
        else
          # when sourcedb is not user's sourcedb
          unless self.docs.include?(divs.first)
            self.docs << divs
            num_added += divs.size
          end
        end
      else
        if options[:sourcedb].include?(Doc::UserSourcedbSeparator)
          # when sourcedb include : 
          if is_current_users_sourcedb
            # when sourcedb is user's sourcedb
            divs, num_failed_user_sourcedb_docs = create_user_sourcedb_docs(docs_array: options[:docs_array])
            num_failed += num_failed_user_sourcedb_docs
          else
            # when sourcedb is not user's sourcedb
            num_failed += options[:docs_array].size
          end
        else
          # when sourcedb is not user generated
          begin
            # when doc_sequencer_ present
            doc_sequence = Object.const_get("DocSequencer#{options[:sourcedb]}").new(sourceid)
            divs_hash = doc_sequence.divs
            divs = Doc.create_divs(divs_hash, :sourcedb => options[:sourcedb], :sourceid => sourceid, :source_url => doc_sequence.source_url)
          rescue
            # when doc_sequencer_ not present
            divs, num_failed_user_sourcedb_docs = create_user_sourcedb_docs({docs_array: options[:docs_array], sourcedb: "#{options[:sourcedb]}#{Doc::UserSourcedbSeparator}#{options[:user].username}"})
            num_failed += num_failed_user_sourcedb_docs
          end
        end
        if divs
          self.docs << divs
          num_created += divs.size
        else
          num_failed += 1
        end
      end
    end  
    return [num_created, num_added, num_failed]   
  end

  def add_doc(sourcedb, sourceid)
    imported, added, failed, message = 0, 0, 0
    begin
      divs = Doc.find_all_by_sourcedb_and_sourceid(sourcedb, sourceid)
      unless divs.present?
        divs = Doc.import(sourcedb, sourceid)
        imported += 1 if divs.present?
      end
      if divs.present? and !self.docs.include?(divs.first)
        self.docs << divs
        added += 1
      end
    rescue => e
      failed += 1
      message = e.message
    end

    [imported, added, failed, message]
  end


  def create_user_sourcedb_docs(options = {})
    divs = Array.new
    num_failed = 0
    options[:docs_array].each do |doc_array_params|
      # all of columns insert into database need to be included in this hash.
      doc_array_params[:sourcedb] = options[:sourcedb] if options[:sourcedb].present?
      mappings = {
        :text => :body, 
        :sourcedb => :sourcedb, 
        :sourceid => :sourceid, 
        :section => :section, 
        :source_url => :source, 
        :divid => :serial
      }
      doc_params = Hash[doc_array_params.map{|key, value| [mappings[key], value]}].select{|key| key.present? && Doc.attr_accessible[:default].include?(key)}
      doc = Doc.new(doc_params) 
      if doc.valid?
        doc.save
        divs << doc
      else
        num_failed += 1
      end
    end
    return [divs, num_failed]
  end

  def user_presence
    if user.blank?
      errors.add(:user_id, 'is blank') 
    end
  end

  def namespaces_base
    namespaces.find{|namespace| namespace['prefix'] == '_base'} if namespaces.present?
  end

  def base_uri
    namespaces_base['uri'] if namespaces_base.present?
  end

  def namespaces_prefixes
    namespaces.select{|namespace| namespace['prefix'] != '_base'} if namespaces.present?
  end

  # delete empty value hashes
  def cleanup_namespaces
    namespaces.reject!{|namespace| namespace['prefix'].blank? || namespace['uri'].blank?} if namespaces.present?
  end

  def delay_destroy
    begin
      destroy
    rescue
      notices.create({successful: false, method: 'destroy_project'})
    end
  end
end
