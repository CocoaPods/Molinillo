# frozen_string_literal: true
RSpec::Matchers.define :equal_dependency_graph do |expected|
  diffable
  attr_reader :actual, :expected

  match do |actual|
    @expected = expected.to_dot(:edge_label => proc { |e| e.destination.payload.version })
    @actual = actual.to_dot(:edge_label => proc { |e| e.destination.payload.version })
    actual == expected
  end

  failure_message do
    'Expected the two dependency graphs to be equal'
  end
end
