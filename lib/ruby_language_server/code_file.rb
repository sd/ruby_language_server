# frozen_string_literal: true

require 'active_record'
require_relative 'scope_data/base'
require_relative 'scope_data/code_scope'
require_relative 'scope_data/variable'

module RubyLanguageServer
  class CodeFile < ActiveRecord::Base
    has_many :code_scopes, class_name: 'ScopeData::CodeScope', inverse_of: :code_file

    attr_accessor :uri
    attr_accessor :text
    attr_reader :lint_found

    def text=(new_text) # rubocop:disable Lint/DuplicateMethods
      RubyLanguageServer.logger.debug("text= for #{uri}")
      if @text == new_text
        RubyLanguageServer.logger.debug('IT WAS THE SAME!!!!!!!!!!!!')
        return
      end
      @text = new_text

      new_root_scope = ScopeParser.new(text).root_scope
      unless new_root_scope.children.empty?
        self.code_scopes = new_root_scope.self_and_descendants
        @tags = nil
      end
      save!
    end

    SYMBOL_KIND = {
      file: 1,
      'module': 5, # 2,
      namespace: 3,
      package: 4,
      'class': 5,
      'method': 6,
      'singleton method': 6,
      property: 7,
      field: 8,
      constructor: 9,
      enum: 10,
      interface: 11,
      function: 12,
      variable: 13,
      constant: 14,
      string: 15,
      number: 16,
      boolean: 17,
      array: 18
    }.freeze

    # Find the ancestor of this code_scope with a name and return that.  Or nil.
    def ancestor_scope_name(code_scope)
      return_scope = code_scope
      while (return_scope = return_scope.parent)
        return return_scope.name unless return_scope.name.nil?
      end
    end

    def tags
      RubyLanguageServer.logger.debug("Asking about tags for #{uri}")
      return @tags = {} if text.nil? || text == ''

      tags = []
      byebug
      root_scope.self_and_descendants.each do |code_scope|
        next if code_scope.kind == ScopeData::Base::KIND_BLOCK

        name = code_scope.name
        kind = SYMBOL_KIND[code_scope.kind&.to_sym] || 7
        kind = 9 if name == 'initialize' # Magical special case
        scope_hash = {
          name: name,
          kind: kind,
          location: Location.hash(uri, code_scope.top_line)
        }
        container_name = ancestor_scope_name(code_scope)
        scope_hash[:containerName] = container_name if container_name
        tags << scope_hash

        code_scope.variables.each do |variable|
          name = variable.name
          # We only care about counstants
          next unless name =~ /^[A-Z]/

          variable_hash = {
            name: name,
            kind: SYMBOL_KIND[:constant],
            location: Location.hash(uri, variable.line),
            containerName: code_scope.name
          }
          tags << variable_hash
        end
      end
      # byebug
      tags.reject! { |tag| tag[:name].nil? }
      # RubyLanguageServer.logger.debug("Raw tags for #{uri}: #{tags}")
      # If you don't reverse the list then atom? won't be able to find the
      # container and containers will get duplicated.
      @tags = tags.reverse_each do |tag|
        child_tags = tags.select { |child_tag| child_tag[:containerName] == tag[:name] }
        max_line = child_tags.map { |child_tag| child_tag[:location][:range][:end][:line].to_i }.max || 0
        tag[:location][:range][:end][:line] = [tag[:location][:range][:end][:line], max_line].max
      end
      # RubyLanguageServer.logger.debug("Done with tags for #{uri}: #{@tags}")
      # RubyLanguageServer.logger.debug("tags caller #{caller * ','}")
      @tags
    end

    def diagnostics
      # Maybe we should be sharing this GoodCop across instances
      @good_cop ||= GoodCop.new
      @good_cop.diagnostics(@text, @uri)
    end

    def root_scope
      # RubyLanguageServer.logger.error("Asking about root_scope with #{text}")
      # if @refresh_root_scope
      #   new_root_scope = ScopeParser.new(text).root_scope
      #   @root_scope ||= new_root_scope # In case we had NONE
      #   return @root_scope if new_root_scope.children.empty?
      #   self.code_scopes = @root_scope.self_and_descendants
      #
      #   @root_scope = new_root_scope
      #   @refresh_root_scope = false
      #   @tags = nil
      # end
      code_scopes.where(parent: nil).first
    end

    # Returns the context of what is being typed in the given line
    def context_at_location(position)
      lines = text.split("\n")
      line = lines[position.line]
      return [] if line.nil? || line.strip.length.zero?

      LineContext.for(line, position.character)
    end
  end
end
