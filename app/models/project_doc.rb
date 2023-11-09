class ProjectDoc < ActiveRecord::Base
  belongs_to :project
  belongs_to :doc
  has_many :denotations, through: :doc
  has_many :blocks, through: :doc
  has_many :relations, through: :project
  has_many :attrivutes, through: :project
  has_many :modifications, through: :project

  scope :simple_paginate, -> (page, per = 10) {
    page = page.nil? ? 1 : page.to_i
    offset = (page - 1) * per
    offset(offset).limit(per)
  }

  def annotation_about(span, terms, predicates)
    _denotations = denotations_about span, terms, predicates
    _blocks = blocks_about span, terms, predicates

    ids = (_denotations + _blocks).pluck(:id)

    _relations = relations_about ids, terms, predicates
    ids += _relations.pluck(:id)

    Annotation.new(
      project,
      _denotations,
      _blocks,
      _relations,
      attributes_about(ids, predicates),
      modifications_about(ids, terms, predicates)
    )
  end

  def graph_uri
    project.graph_uri + "/docs/sourcedb/#{doc.sourcedb}/sourceid/#{doc.sourceid}"
  end

  def self.reset_counts_denotations
    connection.exec_query "UPDATE project_docs SET (denotations_num) = (SELECT count(*) FROM denotations WHERE denotations.doc_id=project_docs.doc_id and denotations.project_id=project_docs.project_id)"
  end

  def self.reset_counts_relations
    connection.exec_query "UPDATE project_docs SET (relations_num) = (SELECT count(*) FROM relations INNER JOIN denotations ON relations.subj_id=denotations.id and relations.subj_type='Denotation' WHERE denotations.doc_id = project_docs.doc_id and relations.project_id=project_docs.project_id)"
  end

  def self.reset_counts_modifications
    connection.exec_query "UPDATE project_docs SET (modifications_num) = row((SELECT count(*) FROM modifications INNER JOIN denotations ON modifications.obj_id=denotations.id and modifications.obj_type='Denotation' WHERE denotations.doc_id = project_docs.id and modifications.project_id=project_docs.project_id) + (SELECT count(*) FROM modifications INNER JOIN relations ON modifications.obj_id=relations.id and modifications.obj_type='Relation' INNER JOIN denotations ON relations.subj_id=denotations.id and relations.subj_type='Denotations' WHERE denotations.doc_id=project_docs.doc_id and modifications.project_id=project_docs.project_id))"
  end

  def reset_count_denotations
    ActiveRecord::Base.connection.exec_query "UPDATE project_docs SET (denotations_num) = (SELECT count(*) FROM denotations WHERE denotations.doc_id = #{doc_id} AND denotations.project_id = #{project_id}) WHERE project_docs.doc_id = #{doc_id} AND project_docs.project_id = #{project_id}"
  end

  def reset_count_relations
    ActiveRecord::Base.connection.exec_query "UPDATE project_docs SET (relations_num) = (SELECT count(*) FROM relations INNER JOIN denotations ON relations.subj_id=denotations.id AND relations.subj_type='Denotation' WHERE denotations.doc_id = #{doc_id} and relations.project_id = #{project_id}) WHERE project_docs.doc_id = #{doc_id} AND project_docs.project_id = #{project_id}"
  end

  def reset_count_modifications
    ActiveRecord::Base.connection.exec_query "UPDATE project_docs SET (modifications_num) = row((SELECT count(*) FROM modifications INNER JOIN denotations on modifications.obj_id = denotations.id and modifications.obj_type = 'Denotation' WHERE denotations.doc_id = #{doc_id} and modifications.project_id = #{project_id}) + (SELECT count(*) FROM modifications INNER JOIN relations on modifications.obj_id = relations.id and modifications.obj_type = 'Relation' INNER JOIN denotations on relations.subj_id = denotations.id and relations.subj_type = 'Denotations' WHERE denotations.doc_id = #{doc_id} and modifications.project_id = #{project_id})) WHERE project_docs.doc_id = #{doc_id} AND project_docs.project_id = #{project_id}"
  end

  def update_annotations_updated_at
    self.update_attribute(:annotations_updated_at, DateTime.now)
  end

  private

  def denotations_about(span, terms, predicates)
    denotations.in_project(project)
               .in_span(span)
               .with_terms(terms)
               .with_predicates(predicates)
  end

  def blocks_about(span, terms, predicates)
    blocks.in_project(project)
          .in_span(span)
          .with_terms(terms)
          .with_predicates(predicates)
  end

  def relations_about(base_ids, terms, predicates)
    return [] if terms.present? || predicates.present?

    relations.among_denotations(base_ids)
  end

  def attributes_about(base_ids, predicates)
    query = attrivutes.among_entities(base_ids)

    query = query.where(pred: predicates) if predicates

    query
  end

  def modifications_about(base_ids, terms, predicates)
    return [] if terms.present? || predicates.present?

    modifications.among_entities(base_ids)
  end
end
