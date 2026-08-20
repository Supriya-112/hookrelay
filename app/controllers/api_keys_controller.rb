class ApiKeysController < InspectorController
  def index
    @api_keys = account.api_keys.order(created_at: :desc)
    # Passed through the redirect from create: the one moment the key is readable.
    @issued_key = flash[:issued_key]
  end

  def create
    key = ApiKey.issue(account: account, name: params[:name].presence || "API key")

    redirect_to api_keys_path,
                flash: { issued_key: key.token, notice: "Copy this key now — it isn't shown again." }
  end

  def destroy
    account.api_keys.find(params[:id]).destroy!

    redirect_to api_keys_path, notice: "Key revoked."
  end
end
