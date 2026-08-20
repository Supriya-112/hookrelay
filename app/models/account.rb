# Everything in Hookrelay belongs to an account: its sources, and through them the
# events, deliveries and attempts that follow. The inspector only ever reads
# through here, so one account can't reach — or learn the existence of — another's
# webhooks.
class Account < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :sources, dependent: :destroy
  has_many :destinations, through: :sources
  has_many :events, through: :sources
  has_many :deliveries, through: :events

  validates :name, presence: true
end
