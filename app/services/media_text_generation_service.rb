class MediaTextGenerationService
  def initialize(medium)
    @medium = medium
  end

  def call
    validate_medium!

    @medium.file.open do |file|
      generate_text(file.path)
    end
  end

  private

  def generate_text(file_path)
    if @medium.image?
      ImageCaptionService.new(file_path).call
    elsif @medium.audio?
      AudioTranscriptionService.new(file_path).call[:text]
    elsif @medium.video?
      VideoTranscriptionService.new(file_path).call[:text]
    else
      raise ArgumentError, "Unsupported media type: #{@medium.media_type.inspect}"
    end
  end

  def validate_medium!
    raise ArgumentError, "Specified media has no attached file." unless @medium.file.attached?
  end
end
