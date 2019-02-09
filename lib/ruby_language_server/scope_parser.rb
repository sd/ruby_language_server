# frozen_string_literal: true

require 'ripper'
require_relative 'scope_parser_commands/rake_commands'
require_relative 'scope_parser_commands/rspec_commands'
require_relative 'scope_parser_commands/ruby_commands'
require_relative 'scope_parser_commands/rails_commands'

module RubyLanguageServer
  # This class is responsible for processing the generated sexp from the ScopeParser below.
  # It builds scopes that amount to heirarchical arrays with information about what
  # classes, methods, variables, etc - are in each code_scope.
  class SEXPProcessor
    include ScopeParserCommands::RakeCommands
    include ScopeParserCommands::RspecCommands
    include ScopeParserCommands::RailsCommands
    include ScopeParserCommands::RubyCommands
    attr_reader :sexp
    attr_reader :lines
    attr_reader :current_scope

    def initialize(sexp, lines = 1)
      @sexp = sexp
      @lines = lines
      @root_scope = nil
    end

    def root_scope
      return @root_scope unless @root_scope.nil?

      @root_scope = new_root_scope
      @current_scope = @root_scope
      process(@sexp)
      @root_scope
    end

    def process(sexp)
      return if sexp.nil?

      root, args, *rest = sexp
      # RubyLanguageServer.logger.error("Doing #{[root, args, rest]}")
      case root
      when Array
        sexp.each { |child| process(child) }
      when Symbol
        root = root.to_s.gsub(/^@+/, '')
        method_name = "on_#{root}"
        if respond_to? method_name
          send(method_name, args, rest)
        else
          RubyLanguageServer.logger.debug("We don't have a #{method_name} with #{args}")
          process(args)
        end
      when String
        # We really don't do anything with it!
        RubyLanguageServer.logger.debug("We don't do Strings like #{root} with #{args}")
      when NilClass
        process(args)
      when FalseClass
        process(args)
      else
        RubyLanguageServer.logger.warn("We don't respond to the likes of #{root} of class #{root.class}")
      end
    end

    def on_sclass(_args, rest)
      process(rest)
    end

    # foo = bar -- bar is in the vcall.  Pretty sure we don't want to remember this.
    def on_vcall(_args, rest)
      # Seriously - discard args.  Maybe process rest?
      process(rest)
    end

    def on_program(args, _rest)
      process(args)
    end

    def on_var_field(args, rest)
      (_, name, (line, column)) = args
      return if name.nil?

      if name.start_with?('@')
        add_ivar(name, line, column)
      else
        add_variable(name, line, column)
      end
      process(rest)
    end

    def on_bodystmt(args, _rest)
      process(args)
    end

    def on_module(args, rest)
      code_scope = add_scope(args.last, rest, ScopeData::CodeScope::KIND_MODULE)
      assign_subclass(code_scope, rest)
    end

    def on_class(args, rest)
      code_scope = add_scope(args.last, rest, ScopeData::CodeScope::KIND_CLASS)
      assign_subclass(code_scope, rest)
    end

    def assign_subclass(code_scope, sexp)
      return unless !sexp[0].nil? && sexp[0][0] == :var_ref

      (_, (_, name)) = sexp[0]
      code_scope.superclass_name = name
    end

    def on_method_add_block(args, rest)
      code_scope = @current_scope
      process(args)
      process(rest)
      # add_scope(args, rest, ScopeData::CodeScope::KIND_BLOCK)
      unless @current_scope == code_scope
        code_scope.bottom_line = [code_scope&.bottom_line, @current_scope.bottom_line].compact.max
        pop_scope
      end
    end

    def on_do_block(args, rest)
      ((_, ((_, (_, (_, _name, (line, column))))))) = args
      push_scope(ScopeData::CodeScope::KIND_BLOCK, nil, line, column, false)
      process(args)
      process(rest)
      pop_scope
    end

    def on_block_var(args, rest)
      process(args)
      process(rest)
    end

    # Used only to describe subclasses? -- nope
    def on_var_ref(_args, _rest)
      # [:@const, "Bar", [13, 20]]
      # (_, name) = args
      # @current_scope.superclass_name=(name)
    end

    def on_assign(args, rest)
      process(args)
      process(rest)
    end

    def on_def(args, rest)
      add_scope(args, rest, ScopeData::CodeScope::KIND_METHOD)
    end

    # def self.something(par)...
    # [:var_ref, [:@kw, "self", [28, 14]]], [[:@period, ".", [28, 18]], [:@ident, "something", [28, 19]], [:paren, [:params, [[:@ident, "par", [28, 23]]], nil, nil, nil, nil, nil, nil]], [:bodystmt, [[:assign, [:var_field, [:@ident, "pax", [29, 12]]], [:var_ref, [:@ident, "par", [29, 18]]]]], nil, nil, nil]]
    def on_defs(args, rest)
      on_def(rest[1], rest[2..-1]) if args[1][1] == 'self' && rest[0][1] == '.'
    end

    # Multiple left hand side
    # (foo, bar) = somethingg...
    def on_mlhs(args, rest)
      process(args)
      process(rest)
    end

    # ident is something that gets processed at parameters to a function or block
    def on_ident(name, ((line, column)))
      add_variable(name, line, column)
    end

    def on_params(args, rest)
      process(args)
      process(rest)
    end

    # The on_command function idea is stolen from RipperTags https://github.com/tmm1/ripper-tags/blob/master/lib/ripper-tags/parser.rb
    def on_command(args, rest)
      # [:@ident, "public", [6, 8]]
      (_, name, (line, _column)) = args

      method_name = "on_#{name}_command"

      return send(method_name, line, args, rest) if respond_to? method_name

      RubyLanguageServer.logger.debug("We don't have a #{method_name} with #{args}")

      case name
      when 'public', 'private', 'protected'
        # FIXME: access control...
        process(rest)
      when 'delegate'
        # on_delegate(*args[0][1..-1])
      when 'def_delegator', 'def_instance_delegator'
        # on_def_delegator(*args[0][1..-1])
      when 'def_delegators', 'def_instance_delegators'
        # on_def_delegators(*args[0][1..-1])
      end
    end

    # The on_method_add_arg function is downright stolen from RipperTags https://github.com/tmm1/ripper-tags/blob/master/lib/ripper-tags/parser.rb
    def on_method_add_arg(call, args)
      call_name = call && call[0]
      first_arg = args && args[0] == :args && args[1]

      if call_name == :call && first_arg
        if args.length == 2
          # augment call if a single argument was used
          call = call.dup
          call[3] = args[1]
        end
        call
      elsif call_name == :fcall && first_arg
        name, line = call[1]
        case name
        when 'alias_method' # this is an fcall
          [:alias, args[1][0], args[2][0], line] if args[1] && args[2]
        when 'define_method' # this is an fcall
          [:def, args[1][0], line]
        when 'public_class_method', 'private_class_method', 'private', 'public', 'protected'
          access = name.sub('_class_method', '')

          if args[1][1] == 'self'
            klass = 'self'
            method_name = args[1][2]
          else
            klass = nil
            method_name = args[1][1]
          end

          [:def_with_access, klass, method_name, access, line]
          # when 'code_scope', 'named_scope'
          #   [:rails_def, :code_scope, args[1][0], line]
          # when /^attr_(accessor|reader|writer)$/
          #   gen_reader = Regexp.last_match(1) != 'writer'
          #   gen_writer = Regexp.last_match(1) != 'reader'
          #   args[1..-1].each_with_object([]) do |arg, gen|
          #     gen << [:def, arg[0], line] if gen_reader
          #     gen << [:def, "#{arg[0]}=", line] if gen_writer
          #   end
          # when 'has_many', 'has_and_belongs_to_many'
          #   a = args[1][0]
          #   kind = name.to_sym
          #   gen = []
          #   unless a.is_a?(Enumerable) && !a.is_a?(String)
          #     a = a.to_s
          #     gen << [:rails_def, kind, a, line]
          #     gen << [:rails_def, kind, "#{a}=", line]
          #     if (sing = a.chomp('s')) != a
          #       # poor man's singularize
          #       gen << [:rails_def, kind, "#{sing}_ids", line]
          #       gen << [:rails_def, kind, "#{sing}_ids=", line]
          #     end
          #   end
          #   gen
          # when 'belongs_to', 'has_one'
          #   a = args[1][0]
          #   unless a.is_a?(Enumerable) && !a.is_a?(String)
          #     kind = name.to_sym
          #     %W[#{a} #{a}= build_#{a} create_#{a} create_#{a}!].inject([]) do |all, ident|
          #       all << [:rails_def, kind, ident, line]
          #     end
          #   end
        end
      end
    end

    private

    def add_variable(name, line, column, code_scope = @current_scope)
      new_variable = ScopeData::Variable.create!(code_scope: code_scope, name: name, line: line, column: column)
      # blocks don't declare their first line in the parser
      code_scope.top_line ||= line
      code_scope.variables << new_variable unless code_scope.has_variable_or_constant?(new_variable)
    end

    def add_ivar(name, line, column)
      code_scope = @current_scope
      unless code_scope == root_scope
        ivar_kinds = [ScopeData::Base::KIND_CLASS, ScopeData::Base::KIND_MODULE]
        while !ivar_kinds.include?(code_scope.kind) && !code_scope.parent.nil?
          code_scope = code_scope.parent
        end
      end
      add_variable(name, line, column, code_scope)
    end

    def add_scope(args, rest, type)
      (_, name, (line, column)) = args
      code_scope = push_scope(type, name, line, column)
      process(rest)
      pop_scope
      code_scope
    end

    def type_is_class_or_module(type)
      [RubyLanguageServer::ScopeData::Base::KIND_CLASS, RubyLanguageServer::ScopeData::Base::KIND_MODULE].include?(type)
    end

    def push_scope(type, name, top_line, column, close_siblings = true)
      close_sibling_scopes(top_line) if close_siblings
      # The default root code_scope is Object.  Which is fine if we're adding methods.
      # But if we're adding a class, we don't care that it's in Object.
      byebug if type == ScopeData::CodeScope::KIND_BLOCK
      new_scope =
        if (type_is_class_or_module(type) && (@current_scope == root_scope))
          ScopeData::CodeScope.new(kind: type, name: name, top_line: top_line, column: column)
        else
          ScopeData::CodeScope.new(parent: @current_scope, kind: type, name: name, top_line: top_line, column: column)
        end
      new_scope.bottom_line = @lines
      if new_scope.parent.nil? # was it a class or module at the root
        root_scope.children << new_scope
      else
        @current_scope.children << new_scope
      end
      @current_scope = new_scope
    end

    # This is a very poor man's "end" handler because there is no end handler.
    # The notion is that when you start the next code_scope, all the previous peers and unclosed descendents of the previous peer should be closed.
    def close_sibling_scopes(line)
      parent = @current_scope
      parent&.descendants&.each { |code_scope| code_scope.bottom_line = [code_scope.bottom_line, line - 1].compact.min }
    end

    def pop_scope
      @current_scope = @current_scope.parent || root_scope # in case we are leaving a root class/module
    end

    def new_root_scope
      ScopeData::CodeScope.new do |code_scope|
        code_scope.kind = ScopeData::CodeScope::KIND_ROOT
        code_scope.name = nil
      end
    end
  end

  # This class builds on Ripper's sexp processor to add ruby and rails magic.
  # Specifically it knows about things like alias, attr_*, has_one/many, etc.
  # It adds the appropriate definitions for those magic words.
  class ScopeParser < Ripper
    attr_reader :root_scope

    def initialize(text)
      text ||= '' # empty is the same as nil - but it doesn't crash
      begin
        sexp = self.class.sexp(text)
      rescue TypeError => exception
        RubyLanguageServer.logger.error("Exception in sexp: #{exception} for text: #{text}")
      end
      processor = SEXPProcessor.new(sexp, text.split("\n").length)
      @root_scope = processor.root_scope
    end
  end
end
