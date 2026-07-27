# Reads back one of the host-tool checks recorded by SetupController. A check
# counts as verified only when both the value and its timestamp are present,
# so clearing either one puts the card back into "not verified".
module IntegrationStatus
  def self.for(key)
    value = Setting[key]
    checked_at = Setting["#{key}_checked_at"]
    return { ok: false } if value.blank? || checked_at.blank?

    { ok: true, details: value, checked_at: Time.iso8601(checked_at) }
  end
end
