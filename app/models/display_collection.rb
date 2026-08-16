class DisplayCollection < ApplicationRecord
  belongs_to :display
  belongs_to :collection

  validates :collection_id, uniqueness: { scope: :display_id }
  validates :weight, numericality: { greater_than: 0 }
end
