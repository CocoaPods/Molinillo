# frozen_string_literal: true

require 'spec_helper'
require 'spec_helper/naive_resolver'

describe 'fuzzing' do
  CONSTRAINTS = %w(<= ~> > < >= =).freeze
  let(:dependencies) do
    index.specs.keys.sample(Random.rand(5)).
      map do |d|
      Gem::Dependency.new(
        d,
        "#{CONSTRAINTS.sample} #{Random.rand(2)}.#{Random.rand(2)}"
      )
    end
  end
  let(:index_class) { Molinillo::TestIndex }
  let(:index) { index_class.from_fixture('fuzz') }
  let(:ui) { Molinillo::TestUI.new }
  let(:resolver) { Molinillo::Resolver.new(index, ui) }

  subject { resolver.resolve(dependencies) }

  def validate_dependency_graph_from(graph, dependency)
    vertex = graph.vertex_named(dependency.name)
    spec = vertex.payload
    expect(dependency.requirement).to be_satisfied_by(spec.version)
    expect(spec.dependencies).to match_array(vertex.outgoing_edges.map(&:requirement))
    spec.dependencies.each do |d|
      validate_dependency_graph_from(graph, d)
    end
  end

  def validate_dependency_graph(graph)
    dependencies.each do |d|
      validate_dependency_graph_from(graph, d)
    end
  end

  def all_possible_graphs
    dependencies.reduce([]) { |d| strings(graphs, d) }
  end

  let(:naive) { Molinillo::NaiveResolver.resolve(index, dependencies) }

  def validate_unresolvable(error)
    expect(naive).to be_nil,
                     'Got an error resolving but the naive resolver found ' \
                     "#{naive && naive.map(&:payload).map(&:to_s)}:\n#{error}"
  end

  def self.fuzz!(seeds = [])
    Molinillo::INDICES.each do |ic|
      context "with #{ic.to_s.split('::').last}" do
        around(:example) do |ex|
          old_seed = Random::DEFAULT.seed
          ex.run
          Random.srand old_seed
        end

        let(:index_class) { ic }
        seeds.each do |seed|
          it "fuzzes with seed #{seed}" do
            Random.srand seed
            graph, error = begin
              subject
              [subject, nil]
            rescue => e
              [nil, e]
            end
            validate_dependency_graph(graph) if graph
            validate_unresolvable(error) if error

            if naive
              expect(graph).to equal_dependency_graph(naive)
            else
              expect(graph).to be_nil, "#{graph && graph.map(&:payload).map(&:to_s)} vs nil"
            end
          end
        end
      end
    end
  end

  fuzz! [
    8,
    9,
    125,
    188,
    666,
    7_898_789,
    0,
    3,
  ].concat(Array.new(ENV.fetch('MOLINILLO_FUZZER', '0').to_i) { Random.rand })
end if RUBY_VERSION >= '1.9' && !%w[rbx].include?(Gem.ruby_engine)
