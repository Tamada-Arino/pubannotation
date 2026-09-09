class AddTextToMediaTranscripts < ActiveRecord::Migration[8.1]
  def change
    add_column :media_transcripts, :text, :text
  end
end
