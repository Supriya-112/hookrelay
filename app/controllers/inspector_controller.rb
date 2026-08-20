# Base for the pages a person looks at. Signing in is required — the concern in
# ApplicationController sees to that — and everything here reads through the
# signed-in account, never through the models directly.
class InspectorController < ApplicationController
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # Declared here rather than in ApplicationController, which ingest also inherits
  # from and which has to accept whatever a provider sends.
  allow_browser versions: :modern

  private

  # Reading through the account is what keeps one account out of another's
  # webhooks: a request for someone else's source doesn't 403, it 404s, so nobody
  # learns whether that record exists at all.
  def account
    Current.account
  end
end
