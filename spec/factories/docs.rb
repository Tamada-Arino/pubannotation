FactoryBot.define do
  factory :doc do
    sourcedb { "PubMed" }
    sequence(:sourceid) { _1.to_s }
    body { "This is a test.\nTest are implemented.\nImplementation is difficult." }

    trait :with_annotation do
      after(:create) do |doc, _|
        project = create(:project, accessibility: 1)
        create(:project_doc, doc: doc, project: project)

        denotation1 = create(:denotation, doc: doc, project: project)
        denotation2 = create(:object_denotation, doc: doc, project: project)
        create(:relation, project: project, doc: doc, hid: "R1", subj: denotation1, obj: denotation2, pred: 'predicate')
        create(:attrivute, project: project, doc: doc, hid: "A1", subj: denotation1, obj: 'Protein', pred: 'type')

        block1 = create(:block, doc: doc, project: project)
        block2 = create(:second_block, doc: doc, project: project)
        create(:relation, hid: "S1", project: project, doc: doc, subj: block1, obj: block2, pred: 'next')
        create(:attrivute, project: project, doc: doc, hid: "A2", subj: block1, obj: 'true', pred: 'suspect')
      end
    end

    trait :with_private_annotation do
      after(:create) do |doc, _|
        project = create(:project, accessibility: 0)
        create(:project_doc, doc: doc, project: project)

        denotation1 = create(:denotation, doc: doc, project: project)
        denotation2 = create(:object_denotation, doc: doc, project: project)
        create(:relation, project: project, doc: doc, hid: "R1", subj: denotation1, obj: denotation2, pred: 'predicate')
        create(:attrivute, project: project, doc: doc, hid: "A1", subj: denotation1, obj: 'Protein', pred: 'type')

        block1 = create(:block, doc: doc, project: project)
        block2 = create(:second_block, doc: doc, project: project)
        create(:relation, hid: "S1", project: project, doc: doc, subj: block1, obj: block2, pred: 'next')
        create(:attrivute, project: project, doc: doc, hid: "A2", subj: block1, obj: 'true', pred: 'suspect')

        # Do not confuse document accessibility with project accessibility.
        # Have an empty project that is accessible.
        project2 = create(:project, accessibility: 1)
        create(:project_doc, doc: doc, project: project2)
      end
    end
  end
end
