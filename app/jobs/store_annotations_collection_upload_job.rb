class StoreAnnotationsCollectionUploadJob < ApplicationJob
  queue_as :low_priority

  def perform(project, filepath, options)
    # read the filenames of json files into the array filenames
    filenames, dir_path = read_filenames(filepath)

    # initialize the counter
    prepare_progress_record(filenames.length)

    # initialize necessary variables
    @is_sequenced = false
    @longest_processing_time = 0

    batch_item = BatchItem.new
    threads = []

    filenames.each_with_index do |jsonfile, i|
      json_string = File.read(jsonfile)
      begin
        validated_annotations = ValidatedAnnotations.new(json_string)
      rescue JSON::ParserError
        raise "[#{File.basename(jsonfile)}] JSON parse error. Not a valid JSON object."
      end

      # Add annotations to transaction.
      batch_item << validated_annotations

      # Save annotations when enough transactions have been stored.
      if batch_item.enough?
        threads << execute_batch(project, options, batch_item)
        batch_item = BatchItem.new
      end

      @job&.update_attribute(:num_dones, i + 1)
      check_suspend_flag
    end

    # Process the remaining batch items.
    threads << execute_batch(project, options, batch_item)
    threads.each(&:join)

    @job&.update_attribute(:num_dones, filenames.length)

    if @is_sequenced
      ActionController::Base.new.expire_fragment('sourcedb_counts')
      ActionController::Base.new.expire_fragment('docs_count')
    end

    File.unlink(filepath)
    FileUtils.rm_rf(dir_path) unless dir_path.nil?
    true
  end

  def job_name
    'Upload annotations'
  end

  private

  def execute_batch(project, options, batch_item)
    num_sequenced = store_docs(project, batch_item.source_ids_list)
    @is_sequenced = true if num_sequenced > 0
    StoreAnnotationsCollection.new(project, batch_item.annotation_transaction, options, @job).call
  end

  def store_docs(project, ids_list)
    source_dbs_changed = []
    total_num_sequenced = 0

    ids_list.each do |ids|
      num_added, num_sequenced, messages = project.add_docs(ids)
      source_dbs_changed << ids.db if num_added > 0
      total_num_sequenced += num_sequenced
      messages.each do |message|
        @job&.add_message(message.class == Hash ? message : { body: message[0..250] })
      end
    end

    if source_dbs_changed.present?
      ActionController::Base.new.expire_fragment("sourcedb_counts_#{project.name}")
      ActionController::Base.new.expire_fragment("count_docs_#{project.name}")
      source_dbs_changed.each { |sdb| ActionController::Base.new.expire_fragment("count_#{sdb}_#{project.name}") }
    end

    total_num_sequenced
  end

  def read_filenames(filepath)
    dirpath = nil
    filenames = if filepath.end_with?('.json')
                  Dir.glob(filepath)
                else
                  dirpath = File.join('tmp', File.basename(filepath, ".*"))
                  unpack_cmd = "mkdir #{dirpath}; tar -xzf #{filepath} -C #{dirpath}"
                  unpack_success_p = system(unpack_cmd)
                  raise IOError, "Could not unpack the archive file." unless unpack_success_p
                  Dir.glob(File.join(dirpath, '**', '*.json'))
                end.sort
    [filenames, dirpath]
  end
end
