# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeData::Variable do
  # def initialize(parent = nil, type = KIND_ROOT, name = '', top_line = 1, _column = 1)
  let(:code_scope) { RubyLanguageServer::ScopeData::CodeScope.new(parent: nil, kind: RubyLanguageServer::ScopeData::Base::KIND_CLASS, name: 'some_scope', top_line: 1, bottom_line: 100) }
  let(:variable) { RubyLanguageServer::ScopeData::Variable.new(code_scope: code_scope, name: 'some_varible', line: 2, column: 2) }
  let(:constant) { RubyLanguageServer::ScopeData::Variable.new(code_scope: code_scope, name: 'SOME_CONSTANT', line: 2, column: 2) }
  let(:ivar) { RubyLanguageServer::ScopeData::Variable.new(code_scope: code_scope, name: '@some_ivar', line: 2, column: 2) }

  describe '.constant?' do
    it 'should work!' do
      refute(variable.constant?)
      refute(ivar.constant?)
      assert(constant.constant?)
    end
  end
end
