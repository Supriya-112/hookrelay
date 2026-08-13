class Event < ApplicationRecord
  belongs_to :source
  has_many :deliveries, dependent: :destroy
end
