# frozen_string_literal: true

require "digest"
require "net/http"
require "uri"

# The Play store listing text (app/fastlane/metadata/android/<locale>/) and the edit that uploads
# it: lanes `android listing` and `android listing_check`, docs/RELEASE.md "Store listing upload".
# The client is supply's Supply::Client (or a test double with the same methods).
module PlayListing
  # Play Console's limits, in Unicode code points (check.mjs counts the same way).
  LIMITS = { "title" => 30, "short_description" => 80, "full_description" => 4000 }.freeze
  ONE_LINE = %w[title short_description].freeze
  # Legal LK1 (2026-11-26): the live de-DE sentence the staged listing replaces.
  LK1_SENTENCE = "Kostenlos, ohne Werbung, für den ganzen Haushalt."
  STORE_PAGE_LANGUAGE = { "de-DE" => %w[de DE], "en-US" => %w[en US] }.freeze

  # The lane turns this into a plain fastlane error; anything else is a bug and keeps its trace.
  class Refused < StandardError; end

  module_function

  # { "de-DE" => { "title" => ..., "short_description" => ..., "full_description" => ... }, ... }.
  # A file's text is the field's value without its trailing newline. Anything else in a locale
  # folder (images, screenshots, video.txt, changelogs) refuses: no lane uploads those, and
  # LISTING.md / N-354 decide when one may be staged.
  def load(dir)
    locales = Dir.children(dir).select { |c| File.directory?(File.join(dir, c)) }.sort
    raise Refused, "no locale folders in #{dir}" if locales.empty?

    errors = []
    texts = locales.to_h do |locale|
      folder = File.join(dir, locale)
      extra = Dir.children(folder).sort - LIMITS.keys.map { |f| "#{f}.txt" }
      errors << "#{locale}: #{extra.join(', ')} not allowed (only #{LIMITS.keys.join(', ')})" unless extra.empty?
      fields = LIMITS.keys.to_h do |field|
        path = File.join(folder, "#{field}.txt")
        unless File.file?(path)
          errors << "#{locale}: #{field}.txt missing"
          next [field, nil]
        end
        [field, File.read(path, encoding: "UTF-8").delete_suffix("\n")]
      end
      [locale, fields]
    end
    texts.each do |locale, fields|
      fields.each do |field, text|
        next if text.nil?

        errors << "#{locale}/#{field}: empty" if text.strip.empty?
        errors << "#{locale}/#{field}: #{text.length} > #{LIMITS[field]} characters" if text.length > LIMITS[field]
        errors << "#{locale}/#{field}: must be one line" if ONE_LINE.include?(field) && text.include?("\n")
      end
    end
    raise Refused, errors.join("; ") unless errors.empty?

    texts
  end

  # Legal's hash: sha256 of the text with no trailing newline (printf '%s').
  def sha256(text)
    Digest::SHA256.hexdigest(text.to_s)
  end

  def store_page_url(package_name, locale = "de-DE")
    hl, gl = STORE_PAGE_LANGUAGE.fetch(locale, ["en", "US"])
    "https://play.google.com/store/apps/details?id=#{package_name}&hl=#{hl}&gl=#{gl}"
  end

  # [status, body]; a network failure is [nil, message], which counts as not live.
  def fetch_store_page(package_name, locale = "de-DE")
    response = Net::HTTP.get_response(URI(store_page_url(package_name, locale)))
    [response.code.to_i, response.body.to_s.force_encoding("UTF-8")]
  rescue StandardError => e
    [nil, e.message]
  end

  # Why an upload must not commit now, or []. The listing goes live only after the production
  # release (build 1541 on 1 Dec 2026, held by managed publishing until then) is published: a
  # listing edit committed earlier would put the held release live with it. Play's public store
  # page answers 404 until the app is published, and the production track must carry the build
  # the operator says was just published.
  def blockers(store_page_status:, production_releases:, version_code:)
    found = []
    unless store_page_status == 200
      found << "the Play store page answers #{store_page_status || 'nothing'}, so the production release is not published yet"
    end
    if version_code.to_s !~ /\A\d+\z/
      found << "PLAY_PUBLISHED_VERSION_CODE is not set to the production build just published"
    elsif production_releases.none? { |r| r.status == "completed" && (r.version_codes || []).map(&:to_s).include?(version_code.to_s) }
      found << "production has no completed release with versionCode #{version_code}"
    end
    found
  end

  # In the client's open edit: refuse before anything changes if upload is asked and a blocker
  # stands; set each staged locale's title and descriptions (its video stays); commit on upload,
  # else validate and delete the edit. Any failure deletes the edit, so nothing lands half.
  def publish(client:, texts:, upload:, store_page_status:, version_code:, log:)
    production = client.tracks("production").first&.releases || []
    log.call("Production: #{production.map { |r| "#{r.status} #{(r.version_codes || []).join(',')}" }.join('; ')}")
    found = blockers(store_page_status: store_page_status, production_releases: production, version_code: version_code)
    raise Refused, "Not uploading the listing: #{found.join('; ')}" if upload && found.any?

    found.each { |b| log.call("An upload now would refuse: #{b}") }
    texts.each do |locale, fields|
      current = client.listing_for_language(locale)
      client.update_listing_for_language(language: locale, title: fields["title"],
                                         short_description: fields["short_description"],
                                         full_description: fields["full_description"],
                                         video: current.video)
      log.call("#{locale}: staged (full_description sha256 #{sha256(fields['full_description'])})")
    end
    if upload
      client.commit_current_edit!
      log.call("Committed the listing for #{texts.keys.join(', ')}")
    else
      client.validate_current_edit!
      client.abort_current_edit
      log.call("Validated only (RELEASE_UPLOAD is not true); nothing changed on Play")
    end
  rescue StandardError
    begin
      client.abort_current_edit
    rescue StandardError => e
      log.call("Could not delete the edit (Play expires it): #{e.message}")
    end
    raise
  end

  # Reads Play's listing in the client's open edit, then deletes the edit. Returns one line per
  # field that differs from the repo, [] when every staged field matches.
  def read_back(client:, texts:, log:)
    texts.flat_map do |locale, fields|
      listing = client.listing_for_language(locale)
      fields.filter_map do |field, text|
        live = listing.public_send(field).to_s
        log.call("Play #{locale}/#{field}: sha256 #{sha256(live)}, repo #{sha256(text)}")
        "#{locale}/#{field}: Play has sha256 #{sha256(live)}, the repo #{sha256(text)}" unless live == text
      end
    end
  ensure
    client.abort_current_edit
  end

  # The full description as Play's public page shows it ([nil] when the page has none).
  def public_description(html)
    match = html.match(/data-g-id="description"[^>]*>(.*?)<\/div>/m)
    return nil unless match

    entities = { "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'", "nbsp" => " " }
    match[1].gsub(%r{<br\s*/?>}i, "\n").gsub(/<[^>]+>/, "")
            .gsub(/&(#x\h+|#\d+|\w+);/i) do
              code = Regexp.last_match(1)
              if code.start_with?("#x", "#X") then [code[2..].hex].pack("U")
              elsif code.start_with?("#") then [code[1..].to_i].pack("U")
              else entities.fetch(code, "&#{code};")
              end
            end
  end

  # Mismatch lines for the public page of one locale; whitespace is compared collapsed, because
  # the page renders line breaks as markup.
  def public_mismatches(locale:, status:, html:, text:)
    return ["#{locale}: the Play store page answers #{status || 'nothing'}"] unless status == 200

    live = public_description(html)
    return ["#{locale}: no description on the Play store page"] if live.nil?

    found = []
    found << "#{locale}: the store page still has „#{LK1_SENTENCE}“ (Legal LK1)" if live.include?(LK1_SENTENCE)
    squash = ->(s) { s.gsub(/\s+/, " ").strip }
    found << "#{locale}: the store page's description differs from the repo" unless squash.call(live) == squash.call(text)
    found
  end
end
