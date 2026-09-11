class MediaDocCreationService
  # media_transcript is expected to already be persisted (with doc: nil) by the caller.
  def self.call(project, medium, user, attributes, media_transcript)
    hdoc = Doc.hdoc_normalize!(
      {
        **attributes,
        username: user.username,
        body: media_transcript.text,
        medium_id: medium.id
      },
      user,
      user.root?
    )

    doc = Doc.store_hdoc!(hdoc)

    # Wrapped together so a failure here doesn't leave a doc visible in the project without its transcript linked.
    ActiveRecord::Base.transaction do
      media_transcript.update!(doc:)
      project.add_doc!(doc)
    end

    doc
  end
end
