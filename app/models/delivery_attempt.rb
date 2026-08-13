class DeliveryAttempt < ApplicationRecord
  belongs_to :delivery

  # A response arrived when status_code is set; otherwise error explains why not.
  def ok?
    status_code.present? && status_code.between?(200, 299)
  end
end
