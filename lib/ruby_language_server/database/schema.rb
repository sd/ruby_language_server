# frozen_string_literal: true

require 'active_record'

module RubyLanguageServer
  module Database
    module Schema
      class << self
        def setup(database_path = nil)
          database_path ||= RubyLanguageServer::ProjectManager.root_path + 'ruby_language_server'
          connection_hash = {
            adapter: 'sqlite3',
            database: database_path
            # dbfile: database_path
          }
          ActiveRecord::Base.establish_connection(connection_hash)

          ActiveRecord::Schema.define do
            # self.verbose = false

            # enable_extension "plpgsql"
            # enable_extension "pgcrypto"

            create_table(:code_files, force: true) do |t|
              t.text :path
              t.datetime :modified_at
            end

            create_table(:scopes, force: true) do |t|
              t.integer  :file_id
              t.text     :path
              t.datetime :modified_at

              t.string  :name            # method
              t.string  :superclass_name # superclass name
              t.integer :superclass_id
              t.string  :superclass      # superclass name
              # t.string: full_name     # ?
              t.string  :parent_name     # parent scope name
              t.integer :parent_id       # parent scope name
              t.integer :top_line        # first line
              t.integer :bottom_line     # last line
              t.integer :depth           # how many parent scopes
            end
          end
        end
      end
    end
  end
end
