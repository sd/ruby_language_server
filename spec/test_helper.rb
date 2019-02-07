# frozen_string_literal: true

require 'pry'
require 'minitest/color'
require_relative '../lib/ruby_language_server'

require 'minitest/autorun'

module Minitest
  class Test
    RubyLanguageServer::Database::Schema.setup
  end
end
