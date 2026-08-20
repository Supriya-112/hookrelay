require "test_helper"

class RegistrationTest < ActionDispatch::IntegrationTest
  # The fixtures give the app a user, so setup here is mostly "pretend nobody has
  # claimed this install yet".
  setup { User.delete_all }

  test "the first person to arrive creates the account and is signed in" do
    assert_difference [ -> { Account.count }, -> { User.count } ], 1 do
      post registration_path, params: {
        account_name: "Acme", email_address: "owner@example.com",
        password: "long-enough-password", password_confirmation: "long-enough-password"
      }
    end

    assert_redirected_to root_path
    assert_equal "Acme", User.sole.account.name
    follow_redirect!
    assert_response :success, "and lands inside the app, not back at the sign-in page"
  end

  test "an account is not created when the passwords don't match" do
    assert_no_difference [ -> { Account.count }, -> { User.count } ] do
      post registration_path, params: {
        account_name: "Acme", email_address: "owner@example.com",
        password: "one-password", password_confirmation: "another-password"
      }
    end

    assert_response :unprocessable_entity
  end

  test "the setup form is closed once someone has claimed the install" do
    Account.create!(name: "Acme").users.create!(email_address: "owner@example.com", password: "password")

    get new_registration_path
    assert_redirected_to new_session_path

    assert_no_difference -> { Account.count } do
      post registration_path, params: {
        account_name: "Interloper", email_address: "someone@example.com",
        password: "long-enough-password", password_confirmation: "long-enough-password"
      }
    end
  end

  test "signing in on a fresh install offers setup instead" do
    get new_session_path

    assert_redirected_to new_registration_path
  end
end
