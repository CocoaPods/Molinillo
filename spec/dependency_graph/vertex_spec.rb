# frozen_string_literal: true
require 'spec_helper'

module Molinillo
  describe DependencyGraph::Vertex do
    describe 'In general' do
      before do
        @vertex = Molinillo::DependencyGraph::Vertex.new('Name', nil)
      end

      it 'resets hash value when name changes' do
        expect(@vertex.hash_value).to be_nil
        original_hash = @vertex.hash
        expect(@vertex.hash_value).not_to be_nil
        @vertex.name = 'NewName'
        expect(@vertex.hash_value).to be_nil
        new_hash = @vertex.hash
        expect(original_hash).not_to eql(new_hash)
      end
    end
  end
end
