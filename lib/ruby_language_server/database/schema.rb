# frozen_string_literal: true

require 'active_record'

module RubyLanguageServer
  module Database
    module Schema
      class << self
        def database_directory
          RubyLanguageServer::ProjectManager.root_path + '.ruby_language_server/'
        end

        def database_path
          path = database_directory + 'ruby_language_server.sqlite3'
          Dir.mkdir database_directory
        rescue Exception => exception
          RubyLanguageServer.logger.warn("Could not create database at #{path}: #{exception} - using memory instead.")
          ':memory:'
        end

        def setup
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
              t.text :uri
              t.datetime :modified_at
            end

            create_table(:code_scopes, force: true) do |t|
              t.integer  :code_file_id
              t.text     :path
              t.datetime :modified_at

              t.string  :name            # method
              t.string  :kind
              t.string  :superclass_name # superclass name
              t.integer :superclass_id
              t.string  :superclass      # superclass name
              # t.string: full_name     # ?
              t.string  :parent # parent code_scope name
              # t.integer :parent_id # parent code_scope name
              t.integer :top_line        # first line
              t.integer :column
              t.integer :bottom_line     # last line
              t.integer :depth           # how many parent scopes
            end

            create_table(:variables, force: true) do |t|
              t.integer :code_scope_id
              t.string  :name            # method
              t.string  :kind
              t.integer :line
              t.integer :column
            end
          end
        end
      end
    end
  end
end
