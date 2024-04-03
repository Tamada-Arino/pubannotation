# This seed only for development environment
return if Rails.env.production?

User.create! username: 'admin',
             email: 'admin@pubannotation.org',
             password: 'abc123',
             password_confirmation: 'abc123',
             confirmed_at: Time.now,
             root: true,
             manager: true

Project.create! name: 'First',
                user: User.first,
                accessibility: 1

# To Avoid initialize error, Create admin project.
# Note that if the id is missing teeth, the test will fail in a CI environment.
i = 0
loop do
  project = Project.create! name: "ForAdmin#{i}",
                            user: User.first,
                            accessibility: 0
  i += 1
  break if project.id == Pubann::Admin::ProjectId
end

Sequencer.create! name: 'PMC',
                  url: 'http://pubmed-sequencer.pubannotation.org/?sourcedb=PMC',
                  parameters: { 'sourceid' => '_sourceid_' },
                  user: User.first

doc = Doc.create! sourcedb: 'PMC',
                  sourceid: 'PMC0000001',
                  body: <<~BODY
                        I am happy to join with you today in what will go down in history as the greatest demonstration for freedom in the history of our nation.
                        
                        Five score years ago, a great American, in whose symbolic shadow we stand today, signed the Emancipation Proclamation. This momentous decree came as a great beacon light of hope to millions of Negro slaves who had been seared in the flames of withering injustice. It came as a joyous daybreak to end the long night of their captivity.
                        
                        But one hundred years later, the Negro still is not free. One hundred years later, the life of the Negro is still sadly crippled by the manacles of segregation and the chains of discrimination. One hundred years later, the Negro lives on a lonely island of poverty in the midst of a vast ocean of material prosperity. One hundred years later, the Negro is still languished in the corners of American society and finds himself an exile in his own land. And so we've come here today to dramatize a shameful condition.
                        BODY
project = doc.projects.create! name: 'Dream',
                     user: User.first,
                     accessibility: 1
t1 = Denotation.create! doc: doc, project: project, hid: 'T1', begin: 58, end: 65, obj: 'history'
t2 = Denotation.create! doc: doc, project: project, hid: 'T2', begin: 115, end: 122, obj: 'history'
t3 = Denotation.create! doc: doc, project: project, hid: 'T3', begin: 169, end: 177, obj: "nation"
t4 = Denotation.create! doc: doc, project: project, hid: 'T4', begin: 866, end: 874, obj: 'nation'
t5 = Denotation.create! doc: doc, project: project, hid: 'T5', begin: 5, end: 10, obj: 'emotion'
t6 = Denotation.create! doc: doc, project: project, hid: 'T6', begin: 332, end: 337, obj: 'Negro'
t7 = Denotation.create! doc: doc, project: project, hid: 'T7', begin: 508, end: 513, obj: 'Negro'
t8 = Denotation.create! doc: doc, project: project, hid: 'T8', begin: 574, end: 578, obj: 'Negro'
t9 = Denotation.create! doc: doc, project: project, hid: 'T9', begin: 698, end: 703, obj: 'Negro'
t10 = Denotation.create! doc: doc, project: project, hid: 'T10', begin: 822, end: 827, obj: 'Negro'
Attrivute.create! doc: doc, project: project, hid: 'A1', subj: t5, pred: 'emotion', obj: true
Attrivute.create! doc: doc, project: project, hid: 'A2', subj: t6, pred: 'role', obj: 'default'
Attrivute.create! doc: doc, project: project, hid: 'A3', subj: t7, pred: 'role', obj: 'default'
doc.divisions.create! begin: 0, end: 137, label: 'p'
doc.divisions.create! begin: 139, end: 473, label: 'p'
doc.divisions.create! begin: 475, end: 990, label: 'p'
doc.blocks.create! project: project, hid: 'B1', begin: 0, end: 137, obj: 'sentence'
doc.blocks.create! project: project, hid: 'B2', begin: 139, end: 257, obj: 'sentence'
doc.blocks.create! project: project, hid: 'B3', begin: 258, end: 304, obj: 'sentence'
doc.blocks.create! project: project, hid: 'B4', begin: 305, end: 473, obj: 'sentence'
doc.blocks.create! project: project, hid: 'B5', begin: 475, end: 522, obj: 'sentence'
doc.blocks.create! project: project, hid: 'B6', begin: 523, end: 658, obj: 'sentence'
doc.blocks.create! project: project, hid: 'B7', begin: 659, end: 792, obj: 'sentence'
doc.blocks.create! project: project, hid: 'B8', begin: 793, end: 990, obj: 'sentence'

Editor.create! user: User.first,
               is_public: true,
               name: 'TextAE',
               url: 'http://textae.pubannotation.org/editor.html?mode=edit',
               parameters: { 'source' => '_annotations_url_' }

Annotator.create! user: User.first,
                  is_public: true,
                  name: 'PD-UBERON-AE-2023',
                  url: 'https://pubdictionaries.org/text_annotation.json?dictionary=UBERON-AE-2023&threshold=0.92&abbreviation=true&longest=true',
                  method: 1,
                  payload: { '_body_' => '_doc_' },
                  max_text_size: 50000,
                  receiver_attribute: 'uberon_id',
                  new_label: 'Body_part',
                  sample: 'We have shown that synthetic multivalent sialyl Lewis x glycans inhibit strongly the adhesion of lymphocytes to endothelium at sites of inflammation.'

doc2 = Doc.create! sourcedb: 'PMC',
                   sourceid: 'PMC0000002',
                   body: <<~BODY
We have shown that synthetic multivalent sialyl Lewis x glycans inhibit strongly the adhesion of lymphocytes to endothelium at sites of inflammation.
BODY

doc2.projects << Project.first
