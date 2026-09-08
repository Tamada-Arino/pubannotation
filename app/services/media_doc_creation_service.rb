class MediaDocCreationService
  def initialize(project:, medium:, user:, attributes:)
    @project = project
    @medium = medium
    @user = user
    @attributes = attributes
  end

  def save_doc(body)
    hdoc = Doc.hdoc_normalize!(
      {
        **@attributes,
        username: @user.username,
        body:,
        medium_id: @medium.id
      },
      @user,
      @user.root?
    )

    doc = Doc.store_hdoc!(hdoc)
    @project.add_doc!(doc)
    doc
  end
end
