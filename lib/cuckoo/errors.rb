# frozen_string_literal: true

class CuckooError < StandardError; end
class DuplicateJobError < CuckooError; end

# Error for interval parsing failures
class ParseError < ArgumentError; end
