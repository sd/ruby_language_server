# frozen_string_literal: true

module RubyLanguageServer
  module ScopeData
    module Base
      KIND_MODULE = :module
      KIND_CLASS = :class
      KIND_METHOD = :method
      KIND_BLOCK = :block
      KIND_ROOT = :root
      KIND_VARIABLE = :variable

      JoinHash = {
        KIND_MODULE => '::',
        KIND_CLASS => '::',
        KIND_METHOD => '#',
        KIND_BLOCK => '>',
        KIND_ROOT => '',
        KIND_VARIABLE => '^'
      }.freeze

      attr_accessor :kind # Type of this code_scope (module, class, block)

      def method?
        kind == KIND_METHOD
      end
    end
  end
end
