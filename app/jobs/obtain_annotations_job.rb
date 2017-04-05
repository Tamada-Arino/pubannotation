class ObtainAnnotationsJob < Struct.new(:project, :docids, :annotator, :options)
	include StateManagement

	def perform
		@job.update_attribute(:num_items, docids.length)
    @job.update_attribute(:num_dones, 0)

    # for asyncronous annotation
    retrieval_queue = []
    @skip_interval = nil

    batch_num = annotator[:batch_num]
    batch_num = 1 if batch_num.nil? || batch_num == 0

    docids.each_slice(batch_num) do |docid_col|
      begin
        project.obtain_annotations(docid_col, annotator, options)
        @job.update_attribute(:num_dones, @job.num_dones + docid_col.length)
      rescue RestClient::Exceptions::Timeout => e
        @job.messages << Message.create({body: "Job execution stopped: #{e.message}"})
        break
      rescue RestClient::ExceptionWithResponse => e
        if e.response.code == 303
          retry_after = e.response.headers[:retry_after].to_i
          if @skip_interval.nil?
            @skip_interval = retry_after / 10
            @skip_interval = 1 if @skip_interval < 1
            @skip_interval = 10 if @skip_interval > 10
          end
          retrieval_queue << {url:e.response.headers[:location], try_at: retry_after.seconds.from_now, retry_after: retry_after}
        elsif e.response.code == 503 # Service Unavailable
          if retrieval_queue.empty?
            @job.messages << Message.create({body: "Job execution stopped: service is unavailable when the queue is empty."})
            break
          end
          process_retrieval_queue(retrieval_queue)
          sleep(@skip_interval)
          retry
        elsif e.response.code == 404
          @job.messages << Message.create({body: "The annotator does not know the path."})
        else
          @job.messages << Message.create({body: "Message from the annotator: #{e.message}"})
        end
      rescue => e
				@job.messages << Message.create({body: e.message})
        break
      end

      process_retrieval_queue(retrieval_queue) unless retrieval_queue.empty?
    end

    until retrieval_queue.empty?
      process_retrieval_queue(retrieval_queue)
      sleep(@skip_interval) unless retrieval_queue.empty?
    end
	end

  def process_retrieval_queue(queue)
    queue.each do |r|
      begin
        result = project.make_request(:get, r[:url])
        annotations_col = (result.class == Array) ? result : [result]

        annotations_col.each_with_index do |annotations, i|
          raise RuntimeError, "Invalid annotation JSON object." unless annotations.respond_to?(:has_key?)
          Annotation.normalize!(annotations, options[:prefix])
        end

        messages = project.store_annotations_collection(annotations_col, options)
        messages.each{|message| @job.messages << Message.create(message)}

        @job.update_attribute(:num_dones, @job.num_dones + annotations_col.length)
        r[:delme] = true
      rescue RestClient::ExceptionWithResponse => e
        if e.response.code == 404 # Not Found
          if r[:try_at] + ([r[:retry_after], @skip_interval].max * 2) < Time.now
            @job.messages << Message.create({body: "Retrieval of annotation failed after trials for 3 times longer than estimation."})
            r[:delme] = true
          end
        elsif e.response.code == 410 # Permanently removed
          @job.messages << Message.create({body: "Annotation result is removed from the server."})
          r[:delme] == true
        else
          @job.messages << Message.create({body: e.message})
        end
      rescue => e
        @job.messages << Message.create({body: e.message})
      end
    end

    queue.delete_if{|r| r[:delme]}
  end
end
