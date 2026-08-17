class ApplicationController < ActionController::Base
  # No browser requirement is declared here. Ingest has to accept whatever a
  # provider sends it, and the generated `allow_browser versions: :modern` answered
  # 406 to any sender whose user agent looks like an old browser — dropping the
  # webhook. The inspector's controllers ask for a modern browser themselves.

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
