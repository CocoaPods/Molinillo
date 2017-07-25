# frozen_string_literal: true

require File.expand_path('../spec_helper', __FILE__)

module Molinillo
  describe NoSuchDependencyError do
    let(:dependency) { Gem::Dependency.new('foo', '>= 1.0') }
    let(:required_by) { [] }

    subject { described_class.new(dependency, required_by) }

    describe '#message' do
      it 'says it is unable to find the spec' do
        expect(subject.message).to eq('Unable to find a specification for `foo (>= 1.0)`')
      end

      context 'when #required_by is not empty' do
        let(:required_by) { %w(spec-1 spec-2) }

        it 'includes the source names' do
          expect(subject.message).to eq(
            'Unable to find a specification for `foo (>= 1.0)` depended upon by `spec-1` and `spec-2`'
          )
        end
      end
    end
  end
end
