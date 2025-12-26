#!/usr/bin/env ruby
# Property-based tests for array parsing
# **Feature: arrays-and-strings, Property 3: String round-trip** (adapted for arrays)
# **Validates: Requirements 1.1, 2.4**

require_relative '../src/lexer'
require_relative '../src/parser'

# Simple property-based testing implementation
class PropertyTest
  def initialize(iterations: 100)
    @iterations = iterations
    @failures = []
  end

  def check(name, &block)
    @iterations.times do |i|
      begin
        result = block.call(i)
        unless result
          @failures << { name: name, iteration: i, error: "Property returned false" }
          return false
        end
      rescue => e
        @failures << { name: name, iteration: i, error: e.message, backtrace: e.backtrace.first(3) }
        return false
      end
    end
    true
  end

  def report
    if @failures.empty?
      puts "All properties passed!"
      true
    else
      puts "FAILURES:"
      @failures.each do |f|
        puts "  #{f[:name]} (iteration #{f[:iteration]}): #{f[:error]}"
        puts "    #{f[:backtrace].join("\n    ")}" if f[:backtrace]
      end
      false
    end
  end
end

# Random generators
def random_identifier(seed)
  letters = ('a'..'z').to_a
  length = (seed % 8) + 1
  (0...length).map { |i| letters[(seed + i * 7) % 26] }.join
end

def random_array_size(seed)
  (seed % 100) + 1  # 1 to 100
end

def random_index(seed, max)
  seed % max
end

# Property 1: Array declaration parsing produces correct AST structure
# For any valid array name and positive size, parsing `let name[size]` 
# should produce an AST node with type :array_decl, correct name and size
def test_array_decl_parsing
  pt = PropertyTest.new(iterations: 100)
  
  passed = pt.check("array_decl_structure") do |seed|
    name = random_identifier(seed)
    size = random_array_size(seed)
    code = "let #{name}[#{size}]"
    
    lexer = Lexer.new(code)
    tokens = lexer.tokenize
    parser = Parser.new(tokens)
    ast = parser.parse
    
    node = ast.first
    node[:type] == :array_decl && 
      node[:name] == name && 
      node[:size] == size
  end
  
  pt.report
  passed
end

# Property 2: Array access parsing produces correct AST structure
# For any valid array name and index expression, parsing `name[index]`
# should produce an AST node with type :array_access, correct name and index
def test_array_access_parsing
  pt = PropertyTest.new(iterations: 100)
  
  passed = pt.check("array_access_structure") do |seed|
    name = random_identifier(seed)
    index = random_index(seed, 100)
    code = "#{name}[#{index}]"
    
    lexer = Lexer.new(code)
    tokens = lexer.tokenize
    parser = Parser.new(tokens)
    ast = parser.parse
    
    node = ast.first
    node[:type] == :array_access && 
      node[:name] == name && 
      node[:index][:type] == :literal &&
      node[:index][:value] == index
  end
  
  pt.report
  passed
end

# Property 3: Array assignment parsing produces correct AST structure
# For any valid array name, index, and value, parsing `name[index] = value`
# should produce an AST node with type :array_assign, correct name, index, and value
def test_array_assign_parsing
  pt = PropertyTest.new(iterations: 100)
  
  passed = pt.check("array_assign_structure") do |seed|
    name = random_identifier(seed)
    index = random_index(seed, 100)
    value = (seed * 17) % 1000
    code = "#{name}[#{index}] = #{value}"
    
    lexer = Lexer.new(code)
    tokens = lexer.tokenize
    parser = Parser.new(tokens)
    ast = parser.parse
    
    node = ast.first
    node[:type] == :array_assign && 
      node[:name] == name && 
      node[:index][:type] == :literal &&
      node[:index][:value] == index &&
      node[:value][:type] == :literal &&
      node[:value][:value] == value
  end
  
  pt.report
  passed
end

# Property 4: Array declaration with expression index in access
# For any array access with variable index, the index should be parsed as expression
def test_array_access_with_variable_index
  pt = PropertyTest.new(iterations: 100)
  
  passed = pt.check("array_access_variable_index") do |seed|
    arr_name = random_identifier(seed)
    idx_name = random_identifier(seed + 1000)  # Different seed for different name
    code = "#{arr_name}[#{idx_name}]"
    
    lexer = Lexer.new(code)
    tokens = lexer.tokenize
    parser = Parser.new(tokens)
    ast = parser.parse
    
    node = ast.first
    node[:type] == :array_access && 
      node[:name] == arr_name && 
      node[:index][:type] == :variable &&
      node[:index][:name] == idx_name
  end
  
  pt.report
  passed
end

# Run all tests
if __FILE__ == $0
  puts "=" * 60
  puts "Property-Based Tests for Array Parsing"
  puts "**Feature: arrays-and-strings, Property 3: String round-trip**"
  puts "**Validates: Requirements 1.1, 2.4**"
  puts "=" * 60
  
  results = []
  
  puts "\n[Test 1] Array declaration parsing..."
  results << test_array_decl_parsing
  
  puts "\n[Test 2] Array access parsing..."
  results << test_array_access_parsing
  
  puts "\n[Test 3] Array assignment parsing..."
  results << test_array_assign_parsing
  
  puts "\n[Test 4] Array access with variable index..."
  results << test_array_access_with_variable_index
  
  puts "\n" + "=" * 60
  if results.all?
    puts "ALL PROPERTY TESTS PASSED"
    exit 0
  else
    puts "SOME PROPERTY TESTS FAILED"
    exit 1
  end
end
