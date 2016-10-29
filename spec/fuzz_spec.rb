require "spec_helper"

trap("INT") { raise "int" }

describe "fuzzing" do
  CONSTRAINTS = %w(<= ~> > < >= =)
  let(:dependencies) { index.specs.keys.sample(Random.rand(5)).map {|d| VersionKit::Dependency.new(d, "#{CONSTRAINTS.sample} #{Random.rand(2)}.#{Random.rand(2)}") } }
  let(:index) { Molinillo::TestIndex.new("fuzz") }
  let(:ui) { Molinillo::TestUI.new }
  let(:resolver) { Molinillo::Resolver.new(index, ui) }

  subject { resolver.resolve(dependencies) }

  def validate_dependency_graph_from(graph, dependency)
    vertex = graph.vertex_named(dependency.name)
    spec = vertex.payload
    expect(dependency).to be_satisfied_by(spec.version)
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
    dependencies.reduce([]) {|d| strings(graphs, d) }
  end

  class NaiveResolver
    def initialize(index, dependencies)
      @index = index
      @dependencies = dependencies
      @activated = Molinillo::DependencyGraph.new
    end

    def resolve
      level = 0
      @dependencies.each { |d| @activated.add_child_vertex(d.name, nil, [nil], d) }
      @activated.tag(level)
      possibilities_by_level = { }
      loop do
        vertex = @activated.find {|a| !a.requirements.empty? && a.payload.nil? }
        break unless vertex
        possibilities = possibilities_by_level[level] ||= @index.search_for(VersionKit::Dependency.new(vertex.name, ">= 0.0.0-a"))
        possibilities.select! do |spec|
          vertex.requirements.all? {|r| r.satisfied_by?(spec.version) && (!spec.version.pre_release? || @index.send(:dependency_pre_release?, r)) } &&
          spec.dependencies.all? {|d| v = @activated.vertex_named(d.name); !v || !v.payload || d.satisfied_by?(v.payload.version) }
        end
        warn "level = #{level} possibilities = #{possibilities.map(&:to_s)} requirements = #{vertex.requirements.map(&:to_s)}"
        if spec = possibilities.pop
          warn "trying #{spec}"
          @activated.set_payload(vertex.name, spec)
          spec.dependencies.each do |d|
            @activated.add_child_vertex(d.name, nil, [spec.name], d)
          end
          level += 1
          warn "tagging level #{level}"
          @activated.tag(level)
          next
        end
        level = possibilities_by_level.reverse_each.find(proc { [-1,nil] }) {|l, p| !p.empty?}.first
        warn "going back to level #{level}"
        possibilities_by_level.reject! {|l,_| l > level }
        return nil if level < 0
        @activated.rewind_to(level)
        @activated.tag(level)
      end

      @activated
    end

    def warn(*); end
  end

  let(:naive) { NaiveResolver.new(index, dependencies).resolve }

  def validate_unresolvable(error)
    expect(naive).to be_nil, "Got an error resolving but the naive resolver found #{naive && naive.map(&:payload).map(&:to_s)}:\n#{error}"
  end

  def self.fuzz!(seeds = [])
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
        expect(graph).to eq(naive), "#{graph && graph.map(&:payload).map(&:to_s)} vs #{naive && naive.map(&:payload).map(&:to_s)}"
      end
    end
  end

  fuzz! [
    8,
    9,
    125,
    188,
    666,
    7898789,
    0.35096144504316984,
    3.14159,
  ].concat(10000.times.map { Random.rand })
end
