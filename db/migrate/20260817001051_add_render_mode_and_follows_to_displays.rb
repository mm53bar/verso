class AddRenderModeAndFollowsToDisplays < ActiveRecord::Migration[8.1]
  def change
    # How an artwork is made to fit the panel.
    #
    #   fill    — crop to the panel's aspect ratio. Right for a dashboard
    #             background, where bars behind a clock would read as broken.
    #   contain — scale the whole picture to fit and matte the remainder. Right
    #             for a screen pretending to be a hanging painting: cropping a
    #             third off a Group of Seven sketch panel to make it 16:9 is not
    #             showing that painting, it is showing part of it. Measured
    #             2026-08-16 — matting rather than cropping took the set both
    #             screens can share from 76 artworks to 117, and the Canadian
    #             collection within it from 5 to 28.
    add_column :displays, :render_mode, :string, null: false, default: "fill"
    add_column :displays, :matte_color, :string, null: false, default: "#111111"

    # A display that shows whatever another display is showing, rendered at its
    # own size and in its own mode. Two screens in different rooms showing the
    # same picture is what makes "notice it on one, read about it on the other"
    # work at all.
    add_reference :displays, :follows_display, null: true,
                  foreign_key: { to_table: :displays }
  end
end
