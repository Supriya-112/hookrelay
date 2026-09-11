require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset renders a link with the user's password reset token" do
    account = Account.create!(name: "Acme")
    user = account.users.create!(email_address: "owner@example.com", password: "password")

    email = PasswordsMailer.reset(user)

    assert_equal [ "owner@example.com" ], email.to
    assert_equal "Reset your password", email.subject

    # The html and text parts render independently, and each call to
    # password_reset_token embeds its own expiry — so the two parts' tokens are
    # both valid but not identical strings. Each is checked by what it actually
    # needs to do: resolve back to this user.
    html_token = email.html_part.body.to_s[%r{/passwords/([^/]+)/edit}, 1]
    text_token = email.text_part.body.to_s[%r{/passwords/([^/]+)/edit}, 1]

    assert_equal user, User.find_by_password_reset_token!(html_token)
    assert_equal user, User.find_by_password_reset_token!(text_token)
  end
end
