# Tracks a single attempt to generate the text (image caption, or audio/video transcript) for
# one Medium. It does not itself create or persist a Doc — DocGenerationFromMediaJob builds
# the Doc separately, from the text this attempt produces, so `status` reflects only whether
# generating that text succeeded, independent of whether a Doc/MediaTranscript ended up
# persisted. This is what lets "not yet processed" and "processing failed" be told apart,
# since neither one leaves any other record behind. A Medium may have more than one task over
# time (e.g. a retry after a failure); there is no uniqueness constraint on medium_id.
#
# This is a dedicated resource rather than an extension of Job because Job is a generic,
# cross-media background-job tracker: it belongs to an organization/Project (not a Medium),
# derives its state from begun_at/ended_at timestamps, tracks progress via num_items/num_dones,
# is user-deletable, and its #destroy bypasses ActiveRecord callbacks via a raw `self.delete`
# (so a `has_many ... dependent: :destroy` on Job would not even fire). Teaching Job to answer
# "what's the transcription status of this Medium" would require generalizing it with a
# polymorphic subject (subject_type/subject_id), spreading transcription-specific concerns
# into every other kind of Job.
#
# It is kept separate from MediaTranscript because that model represents a transcription
# attempt that actually ran to completion — even a blank/no-speech one — while
# MediaTranscriptionTask represents the attempt itself, including states (pending, processing,
# failed) where generation didn't complete at all and no MediaTranscript exists yet.
class MediaTranscriptionTask < ApplicationRecord
  belongs_to :medium
  belongs_to :job, optional: true
  has_one :media_transcript, dependent: :nullify

  validates :status, presence: true

  enum :status, {
    pending: 'pending',
    processing: 'processing',
    succeeded: 'succeeded',
    no_speech: 'no_speech',
    failed: 'failed'
  }

  # Wraps a transcription attempt, transitioning through processing -> succeeded/no_speech/failed
  # and re-raising any error from the block after recording it, so the caller doesn't need to
  # manage the task's status itself. Mirrors `transaction do ... end`. The block is expected to
  # return a MediaTranscript, as MediaTextGenerationService#call does. A blank text (e.g. no
  # speech detected in audio/video, or a blank image caption) is classified as no_speech rather
  # than succeeded — checking text rather than segments directly is what lets this apply to
  # images too, which never have segments to check in the first place.
  def process
    processing!
    media_transcript = yield
    no_speech_detected = media_transcript.text.blank?
    no_speech_detected ? no_speech! : succeeded!
    media_transcript
  rescue StandardError
    failed! unless succeeded? || no_speech?
    raise
  end
end
