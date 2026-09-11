class MediaTextGenerationService
  def initialize(medium)
    @medium = medium
  end

  # Returns an unsaved MediaTranscript. Its text is the caption as-is for an image, or the
  # speech-only text (excluding Whisper's non-speech labels) for audio/video.
  def call
    validate_medium!

    @medium.file.open do |file|
      build_media_transcript(file.path)
    end
  end

  private

  def build_media_transcript(file_path)
    if @medium.image?
      MediaTranscript.new(medium: @medium, text: ImageCaptionService.new(file_path).call)
    elsif @medium.audio?
      speech_only_transcript(AudioTranscriptionService.new(file_path).call)
    elsif @medium.video?
      speech_only_transcript(VideoTranscriptionService.new(file_path).call)
    else
      raise ArgumentError, "Unsupported media type: #{@medium.media_type.inspect}"
    end
  end

  def speech_only_transcript(segments)
    media_transcript = MediaTranscript.new(medium: @medium, segments:)
    media_transcript.text = media_transcript.speech_text
    media_transcript
  end

  def validate_medium!
    raise ArgumentError, "Specified media has no attached file." unless @medium.file.attached?
  end
end
