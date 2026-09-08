class DocGenerationFromMediaJob < ApplicationJob
  include UseJobRecordConcern

  queue_as :general

  def perform(project, medium, user, attributes)
    task = MediaTranscriptionTask.create!(medium:, job: @job)

    body = task.process { MediaTextGenerationService.new(medium).call }

    MediaDocCreationService.new(project:, medium:, user:, attributes:).save_doc(body)
  end

  def job_name
    'Generate doc text from media'
  end
end
