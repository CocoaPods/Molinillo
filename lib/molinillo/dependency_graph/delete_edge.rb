# frozen_string_literal: true

require_relative 'action'
module Molinillo
  class DependencyGraph
    # @!visibility private
    # (see DependencyGraph#delete_edge)
    class DeleteEdge < Action
      # @!group Action

      # (see Action.action_name)
      def self.action_name
        :delete_edge
      end

      # (see Action#up)
      def up(graph)
        edge = make_edge(graph)
        @removed_outgoing = delete_first(edge.origin.outgoing_edges, edge)
        @removed_incoming = delete_first(edge.destination.incoming_edges, edge)
      end

      # (see Action#down)
      def down(graph)
        edge = make_edge(graph)
        edge.origin.outgoing_edges << @removed_outgoing if @removed_outgoing
        edge.destination.incoming_edges << @removed_incoming if @removed_incoming
        edge
      end

      # @!group DeleteEdge

      # @return [String] the name of the origin of the edge
      attr_reader :origin_name

      # @return [String] the name of the destination of the edge
      attr_reader :destination_name

      # @return [Object] the requirement that the edge represents
      attr_reader :requirement

      # @param  [DependencyGraph] graph the graph to find vertices from
      # @return [Edge] The edge this action adds
      def make_edge(graph)
        Edge.new(
          graph.vertex_named(origin_name),
          graph.vertex_named(destination_name),
          requirement
        )
      end

      # Initialize an action to add an edge to a dependency graph
      # @param [String] origin_name the name of the origin of the edge
      # @param [String] destination_name the name of the destination of the edge
      # @param [Object] requirement the requirement that the edge represents
      def initialize(origin_name, destination_name, requirement)
        @origin_name = origin_name
        @destination_name = destination_name
        @requirement = requirement
      end

      private

      # Removes the first edge in `edges` matching `edge`, so that undoing the
      # action restores exactly what was removed (one of several equal edges,
      # or nothing at all if there was no such edge).
      # @return [Edge, nil] the removed edge
      def delete_first(edges, edge)
        index = edges.index do |e|
          e.origin.equal?(edge.origin) && e.destination.equal?(edge.destination) && e.requirement == edge.requirement
        end
        edges.delete_at(index) if index
      end
    end
  end
end
