source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }
ruby '3.3.4'

gem 'rails', '~> 7.2.1'
gem 'rake'
gem 'activerecord-import'

gem 'puma'
gem 'rack-cors'
gem 'sass-rails'

gem 'terser'

gem 'pg'
gem 'friendly_id'
# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.1.0', require: false

group :development do
  gem 'dotenv-rails'
  gem 'web-console'
  gem 'debug'
  gem "stackprof"
end

gem 'text_alignment', '0.12.3'
gem 'pubannotation_evaluator', '~> 3.0.0'
gem 'wice_grid', github: 'ledsun/wice_grid', branch: 'rails_7_1'
gem 'font-awesome-rails'
gem 'jquery-rails'
gem "jquery-ui-rails", github: 'jquery-ui-rails/jquery-ui-rails'
gem 'rails3-jquery-autocomplete'
gem 'facebox-rails', github: 'KishiKyousuke/facebox-rails'
gem 'color-generator'

gem 'rest-client'
gem 'htmlentities'
gem 'libxml-ruby'
gem 'wikipedia-client'
gem 'ruby-dictionary'
gem 'kaminari'
gem 'devise'
gem 'recaptcha'
gem "omniauth-rails_csrf_protection"
gem 'omniauth-google-oauth2'
gem 'rubyzip'
gem 'zip-zip'
gem 'elasticsearch-model', '~> 7.2'
gem 'elasticsearch-rails', '~> 7.2'
gem 'faraday'
gem 'stardog-rb', git: 'https://github.com/jdkim/stardog-rb.git'
gem 'tao_rdfizer', '~> 0.11.3'

# Use to clear page or fragment caches in app/controllers/doc_sweeper.rb
gem 'rails-observers'
gem 'diff-lcs'
gem 'activejob-cancel'
gem 'sidekiq'

gem "foreman"

# For the RSpec
group :development, :test do
  gem 'rspec-rails'
  gem 'factory_bot_rails'
end

# For term search, Union attrivutes term search results and denotations term search results
gem "active_record_union", "~> 1.3"

group :production do
  gem 'unicorn'
end
