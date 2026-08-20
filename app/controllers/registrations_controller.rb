# First-run setup: whoever installs Hookrelay claims it, creating the account and
# its first user. After that this form is closed — a relay reachable from the
# internet shouldn't let a stranger register, and further users are added from the
# console until there's a reason to build invitations.
class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  before_action :refuse_when_already_set_up

  def new
    @user = User.new
  end

  def create
    @user = User.new(email_address: params[:email_address], password: params[:password], password_confirmation: params[:password_confirmation])

    ActiveRecord::Base.transaction do
      @user.account = Account.create!(name: params[:account_name].presence || "Hookrelay")
      @user.save!
    end

    start_new_session_for @user
    redirect_to root_path, notice: "Hookrelay is yours. Create a source to get an ingest URL."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private

  def refuse_when_already_set_up
    return unless User.exists?

    redirect_to new_session_path, alert: "Hookrelay is already set up — sign in instead."
  end
end
