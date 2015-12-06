require File.expand_path('../spec_helper', __FILE__)

module Molinillo
  describe ResolutionState do
    describe DependencyState do
      before do
        @state = described_class.new(
          'name',
          %w(requirement1 requirement2 requirement3),
          DependencyGraph.new,
          'requirement',
          %w(possibility1 possibility),
          0,
          {}
        )
      end

      it 'pops a possibility state' do
        possibility_state = @state.pop_possibility_state
        %w(name requirements activated requirement conflicts).each do |attr|
          expect(possibility_state.send(attr)).to eq(@state.send(attr))
        end
        expect(possibility_state).to be_a(PossibilityState)
        expect(possibility_state.depth).to eq(@state.depth + 1)
        expect(possibility_state.possibilities).to eq(%w(possibility))
      end
    end
  end
end
