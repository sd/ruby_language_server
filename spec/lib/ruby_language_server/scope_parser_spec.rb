# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParser do
  describe 'Small file' do
    before do
      @code_file_lines = <<-SOURCE
      bogus = Some::Bogus
      module Foo
        class Bar
          @bottom = 1

          public def baz(bing, zing)
            zang = 1
            @biz = bing
            @biz = bang
          end

        end

        class Nar < Bar
          attr :top

          private

          def naz(ning)
            @niz = ning
          end
        end

        module Zar
          class << self
            def zoo(par)
              paf = par
            end
          end

          def self.zor(par)
            pax = par
          end
        end

      end
      SOURCE
      @parser = RubyLanguageServer::ScopeParser.new(@code_file_lines)
    end

    describe 'class << self' do
      let(:zar) { @parser.root_scope.self_and_descendants.detect { |child| child.full_name == 'Foo::Zar' } }

      it 'should add methods' do
        assert_equal(%w[zoo zor], zar.children.map(&:name).sort)
      end
    end

    it 'should have a root code_scope' do
      refute_nil(@parser.root_scope)
    end

    it 'should have one module' do
      children = @parser.root_scope.children
      assert_equal(1, children.size)
      m = children.first
      assert_equal('Foo', m.name)
      assert_equal('Foo', m.full_name)
    end

    it 'module should span the whole file' do
      m = @parser.root_scope.children.first
      assert_equal(2, m.top_line)
      # assert_equal(20, m.bottom_line) # Uhhh.  Whatever.
    end

    it 'should have two classes' do
      m = @parser.root_scope.children.first
      children = m.children
      assert_equal(3, children.size)
      bar = m.children.detect { |child| child.full_name == 'Foo::Bar' }
      assert_equal('Bar', bar.name)
      assert_equal('Foo::Bar', bar.full_name)
      nar = m.children.detect { |child| child.full_name == 'Foo::Nar' }
      assert_equal('Nar', nar.name)
      assert_equal('Foo::Nar', nar.full_name)
    end

    it 'should see Nar subclasses Bar' do
      m = @parser.root_scope.children.first
      nar = m.children.detect { |child| child.full_name == 'Foo::Nar' }
      assert_equal('Nar', nar.name)
      assert_equal('Foo::Bar', nar.superclass_name)
    end

    it 'should have a function Foo::Bar#baz' do
      m = @parser.root_scope.children.first
      bar = m.children.first
      baz_function = bar.children.first
      assert_equal('baz', baz_function.name)
      assert_equal(%w[bing zang zing], baz_function.variables.map(&:name).sort)
    end

    it 'should have a couple of ivars for Bar' do
      m = @parser.root_scope.children.first
      bar = m.children.detect { |child| child.full_name == 'Foo::Bar' }
      assert_equal(2, bar.variables.size)
    end

    it 'should have a 3 methods for Nar' do
      m = @parser.root_scope.children.first
      nar = m.children.detect { |child| child.full_name == 'Foo::Nar' }
      assert_equal(3, nar.children.size)
      assert_equal(['top', 'top=', 'naz'], nar.children.map(&:name))
    end

    it 'should have a couple of ivars for Nar' do
      m = @parser.root_scope.children.first
      bar = m.children.detect { |child| child.full_name == 'Foo::Bar' }
      assert_equal(2, bar.variables.size)
    end
  end

  describe 'on_assign' do
    it 'should handle complex lvars' do
      RubyLanguageServer::ScopeParser.new('some.tricky.thing = bob')
    end
  end

  describe 'initialize' do
    it 'should deal with nil' do
      RubyLanguageServer::ScopeParser.new(nil)
    end

    it 'should deal with empty' do
      RubyLanguageServer::ScopeParser.new('')
    end
  end

  describe 'block with compound variable' do
    let(:block_source) do
      <<-BLOCK
      sum_or_average.each do |(date, c), value|
      end
      BLOCK
    end
    let(:scope_parser) { RubyLanguageServer::ScopeParser.new(block_source) }

    it "should parse the names" do
      block_scope = scope_parser.root_scope.children.first
      assert_equal(1, block_scope.top_line)
      assert_equal(2, block_scope.bottom_line)
      assert_equal(%w[date c value], block_scope.variables.map(&:name))
    end
  end

  describe 'block' do
    let(:block_source) do
      <<-RAKE
      class SomeClass
        def some_method
          # Array of [[object, [key, value]], [object2, [key2, value2]]]
          items.each do |item, (key, value)|
            # should see item as a variable
          end
        end
      end
      RAKE
    end
    let(:scope_parser) { RubyLanguageServer::ScopeParser.new(block_source) }

    it 'should find a block with a variable' do
      assert_equal('item', scope_parser.root_scope.self_and_descendants.last.variables.first.name)
    end
  end
end
