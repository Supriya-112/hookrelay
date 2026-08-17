require "ipaddr"
require "resolv"

# Decides whether a destination URL may be delivered to. Destination URLs are
# supplied by whoever owns the source, so without this a delivery could be aimed
# at 127.0.0.1, a neighbouring service on the private network, or the cloud
# metadata endpoint at 169.254.169.254 — and the response body would come back in
# the attempt log, turning the relay into a reader of anything inside its own
# network.
#
# The check runs at delivery time rather than as a validation on Destination,
# because what a hostname resolves to can change after the record is saved.
# Development points destinations at sinks on the same machine, so it opts out
# through HOOKRELAY_ALLOW_PRIVATE_DESTINATIONS.
class DestinationGuard
  # Names that mean "this machine" whatever DNS answers.
  LOOPBACK_NAMES = %w[localhost].freeze

  class << self
    # A reason string when the URL must not be delivered to, or nil when it may.
    # Callers that have already resolved the host (and the tests) can pass the
    # addresses in rather than paying for a second lookup.
    def blocked_reason(url, addresses: nil)
      return nil if allow_private?

      host = host_for(url)
      return "no host to deliver to" if host.blank?
      return "#{host} is this machine" if loopback_name?(host)

      private_ip = first_private_address(addresses || resolve(host))
      return nil if private_ip.nil?
      return "#{host} is a private address" if private_ip.to_s == host

      "#{host} resolves to #{private_ip}, a private address"
    rescue URI::InvalidURIError
      "not a valid URL"
    end

    private

    def allow_private?
      Rails.configuration.x.hookrelay.allow_private_destinations
    end

    def host_for(url)
      # Bracketed IPv6 literals ("http://[::1]/") keep their brackets in URI#host.
      URI.parse(url).host.to_s.downcase.delete_prefix("[").delete_suffix("]")
    end

    def loopback_name?(host)
      LOOPBACK_NAMES.include?(host) || LOOPBACK_NAMES.any? { |name| host.end_with?(".#{name}") }
    end

    def first_private_address(addresses)
      addresses.filter_map { |address| to_ip(address) }.find { |ip| private_address?(ip) }
    end

    def private_address?(ip)
      # ::ffff:10.0.0.1 and friends describe an IPv4 address, so judge the IPv4.
      ip = ip.native if ip.ipv4_mapped?
      ip.loopback? || ip.private? || ip.link_local? || ip.to_i.zero?
    end

    def to_ip(address)
      IPAddr.new(address.to_s)
    rescue IPAddr::Error
      nil
    end

    # A host that won't resolve is left for the HTTP request to fail on: we can't
    # say where it points, and refusing it here would report the wrong reason.
    def resolve(host)
      return [ host ] if to_ip(host) # an address literal needs no lookup

      Resolv.getaddresses(host)
    rescue StandardError
      []
    end
  end
end
