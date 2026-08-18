# Base for the pages a person looks at. The browser requirement lives here rather
# than in ApplicationController, which the ingest endpoint also inherits from and
# which has to accept whatever a provider sends.
class InspectorController < ApplicationController
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :authenticate_inspector

  private

  # Events hold whatever a provider sent, headers included, so a deployment that
  # is reachable before accounts exist (M7) can put a password in front of the
  # inspector by setting HOOKRELAY_INSPECTOR_USER and _PASSWORD. Unset, as in
  # local development, the pages are open.
  def authenticate_inspector
    credentials = Rails.configuration.x.hookrelay.inspector_credentials
    return if credentials.blank?

    authenticate_or_request_with_http_basic("Hookrelay") do |user, password|
      # & rather than && so both comparisons always run, whatever the first says.
      ActiveSupport::SecurityUtils.secure_compare(user, credentials[:user]) &
        ActiveSupport::SecurityUtils.secure_compare(password, credentials[:password])
    end
  end
end
