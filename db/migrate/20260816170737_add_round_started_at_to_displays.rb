class AddRoundStartedAtToDisplays < ActiveRecord::Migration[8.1]
  def change
    # When the current pass through the collection began.
    #
    # Weighting and "show everything before repeating anything" pull against
    # each other: a strict least-recently-shown order guarantees coverage but
    # leaves weight with nothing to do. A round reconciles them — an artwork
    # gets `weight` slots per round, and a new round starts only once every
    # eligible piece has used all of its slots.
    add_column :displays, :round_started_at, :datetime
  end
end
