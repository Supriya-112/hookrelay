class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # A delivery whose event or destination has since been deleted can never run;
  # retrying it would only fail the same way until the queue gives up.
  discard_on ActiveJob::DeserializationError
end
