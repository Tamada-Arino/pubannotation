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

    begin
      # Wrapped together so a failure here doesn't leave a doc visible in the project without its transcript linked.
      ActiveRecord::Base.transaction do
        media_transcript.update!(doc:)
        project.add_doc!(doc)
      end
    rescue StandardError
      # doc survives the rollback above (Doc.store_hdoc! already committed it separately), so
      # it's destroyed explicitly to keep a retry from colliding with its sourcedb/sourceid.
      # Reloaded first: the rolled-back media_transcript.update! left doc's in-memory
      # media_transcript association stale, which would otherwise cascade-destroy that
      # transcript via Doc's dependent: :destroy.
      doc.reload.destroy!
      raise
    end

    doc
  end
end
