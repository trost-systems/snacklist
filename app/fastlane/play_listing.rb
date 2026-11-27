# frozen_string_literal: true

require "digest"
require "net/http"
require "time"
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

  # A production release as Play's releases endpoint reports it, without opening an edit: its
  # lifecycle state without the RELEASE_LIFECYCLE_STATE_ prefix (APPROVED_NOT_PUBLISHED while
  # managed publishing holds it, PUBLISHED once out) and its versionCodes.
  Release = Struct.new(:state, :version_codes)
  HELD = "APPROVED_NOT_PUBLISHED"
  PUBLISHED = "PUBLISHED"
  # Peter K1: launch day, 1 Dec 2026 00:00 Europe/Berlin. PLAY_LISTING_HELD_FROM may only move it
  # later; an earlier value (a typo such as 2026-11-01) would let the held path commit too soon.
  HELD_FROM_FLOOR = Time.new(2026, 12, 1, 0, 0, 0, "+01:00")
  # Play's answer when this app's changes must be sent for review by hand (supply's rescue matches it too).
  NOT_SENT_FOR_REVIEW = "changesNotSentForReview to true"

  # service is supply's AndroidPublisherService (Supply::Client#client).
  def production_releases(service, package_name)
    summaries = service.list_application_track_releases("applications/#{package_name}/tracks/production").releases || []
    summaries.map do |r|
      Release.new(r.release_lifecycle_state.to_s.delete_prefix("RELEASE_LIFECYCLE_STATE_"),
                  (r.active_artifacts || []).map { |a| a.version_code.to_s })
    end
  end

  def describe(releases)
    releases.empty? ? "no releases" : releases.map { |r| "#{r.state} #{r.version_codes.join(',')}" }.join("; ")
  end

  # Why an upload must not commit now, or []. Two orders (docs/RELEASE.md "Store listing upload"):
  # - with the held release (with_held_release): the named build waits under managed publishing
  #   (APPROVED_NOT_PUBLISHED), and it is held_from or later (Peter K1: nothing before launch day),
  #   so one publish puts the release and the listing out together;
  # - after the publish: the named build is PUBLISHED.
  def blockers(production_releases:, version_code:, with_held_release:, held_from:, now: Time.now)
    return ["PLAY_PUBLISHED_VERSION_CODE is not set to the production build"] if version_code.to_s !~ /\A\d+\z/

    release = production_releases.find { |r| r.version_codes.include?(version_code.to_s) }
    return ["production has no release with versionCode #{version_code}"] if release.nil?

    found = []
    if with_held_release
      unless release.state == HELD
        found << "production #{version_code} is #{release.state}, not held by managed publishing (#{HELD}); " \
                 "the held-release path needs it held, the after-publish path needs it #{PUBLISHED}"
      end
      if held_from.nil?
        found << "PLAY_LISTING_HELD_FROM is not set"
      elsif held_from < HELD_FROM_FLOOR
        found << "PLAY_LISTING_HELD_FROM #{held_from.iso8601} is before launch day #{HELD_FROM_FLOOR.iso8601}; " \
                 "it may only move the date later (Peter K1)"
      elsif now < held_from
        found << "the listing may join the held release only from #{held_from.iso8601} (Peter K1)"
      end
    elsif release.state != PUBLISHED
      found << "production #{version_code} is #{release.state}, not #{PUBLISHED} yet"
    end
    found
  end

  # Read only, no edit: which upload path would pass for version_code, and when. Raises Refused
  # unless the build is held or published, the two states an upload path can use.
  def preflight(production_releases:, version_code:, held_from:, now:, log:)
    log.call("Production releases: #{describe(production_releases)}")
    held = blockers(production_releases: production_releases, version_code: version_code, with_held_release: true,
                    held_from: held_from, now: now)
    after = blockers(production_releases: production_releases, version_code: version_code, with_held_release: false,
                     held_from: held_from, now: now)
    log.call("Held-release path: #{held.empty? ? 'an upload would commit now' : held.join('; ')}")
    log.call("After-publish path: #{after.empty? ? 'an upload would commit now' : after.join('; ')}")
    usable = blockers(production_releases: production_releases, version_code: version_code, with_held_release: true,
                      held_from: held_from, now: [now, held_from].compact.max).empty? || after.empty?
    raise Refused, "Neither upload path can use production #{version_code}: #{(held + after).uniq.join('; ')}" unless usable
  end

  # In the client's open edit: refuse before anything changes if upload is asked and a blocker
  # stands; set each staged locale's title and descriptions (its video stays); commit on upload,
  # else validate and delete the edit. Any failure deletes the edit, so nothing lands half.
  # Returns :not_sent_for_review when Play took the commit only with changesNotSentForReview.
  def publish(client:, texts:, upload:, blockers:, log:)
    raise Refused, "Not uploading the listing: #{blockers.join('; ')}" if upload && blockers.any?

    blockers.each { |b| log.call("An upload now would refuse: #{b}") }
    texts.each do |locale, fields|
      current = client.listing_for_language(locale)
      client.update_listing_for_language(language: locale, title: fields["title"],
                                         short_description: fields["short_description"],
                                         full_description: fields["full_description"],
                                         video: current.video)
      log.call("#{locale}: staged (full_description sha256 #{sha256(fields['full_description'])})")
    end
    if upload
      review = commit(client: client, log: log)
      log.call("Committed the listing for #{texts.keys.join(', ')}")
      review
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

  # Play answers some commits with "Please set the query parameter changesNotSentForReview to
  # true" (supply's rescue would then commit silently). Such a commit lands in Play Console as a
  # change nobody sent for review, so it is never published unless Ops sends it by hand.
  def commit(client:, log:)
    client.commit_current_edit!
    :sent_for_review
  rescue StandardError => e
    raise unless e.message.include?(NOT_SENT_FOR_REVIEW)

    log.call("Play refuses to send this edit for review automatically: #{e.message}")
    client.commit_not_sent_for_review!
    log.call(NOT_SENT_WARNING)
    :not_sent_for_review
  end

  NOT_SENT_WARNING = "!!! NOT SENT FOR REVIEW !!! The listing is committed but Google will not review it until " \
                     "Ops sends it by hand: Play Console > Publishing overview > Send changes for review. " \
                     "Then, once Google approves and the change is published, run mode=check."

  # The `android listing` lane. The gate reads production before any edit opens, so a refused
  # upload opens none. Then publish in one edit and, on upload, read every field back in a
  # second. new_client opens an edit per call.
  def run(texts:, upload:, version_code:, production_releases:, new_client:, log:, with_held_release:, held_from:,
          now: Time.now)
    log.call("Production releases: #{describe(production_releases)}")
    found = blockers(production_releases: production_releases, version_code: version_code,
                     with_held_release: with_held_release, held_from: held_from, now: now)
    raise Refused, "Not uploading the listing: #{found.join('; ')}" if upload && found.any?

    review = publish(client: new_client.call, texts: texts, upload: upload, blockers: found, log: log)
    return unless upload

    mismatches = read_back(client: new_client.call, texts: texts, log: log)
    unless mismatches.empty?
      raise Refused, "The listing was committed, but Play's read-back differs from the repo: #{mismatches.join('; ')}. " \
                     "Running the upload again sends the same text (docs/RELEASE.md, Store listing upload)."
    end
    raise Refused, NOT_SENT_WARNING if review == :not_sent_for_review
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

  # Extends supply's Supply::Client, built with rescue_changes_not_sent_for_review: false, so the
  # lane, not supply, decides what a commit without review means.
  module SupplyCommit
    def commit_not_sent_for_review!
      Supply.config.set(:changes_not_sent_for_review, true)
      commit_current_edit!
    ensure
      Supply.config.set(:changes_not_sent_for_review, false)
    end
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

  # Mismatch lines for the public page of one locale. The page renders each line break as <br>,
  # so the text maps back exactly and is compared by sha256.
  def public_mismatches(locale:, status:, html:, text:, log:)
    return ["#{locale}: the Play store page answers #{status || 'nothing'}"] unless status == 200

    live = public_description(html)
    return ["#{locale}: no description on the Play store page"] if live.nil?

    log.call("Store page #{locale}/full_description: sha256 #{sha256(live)}, repo #{sha256(text)}")
    found = []
    found << "#{locale}: the store page still has „#{LK1_SENTENCE}“ (Legal LK1)" if live.include?(LK1_SENTENCE)
    return found if live == text

    squash = ->(t) { t.gsub(/\s+/, " ").strip }
    how = squash.call(live) == squash.call(text) ? "only in whitespace" : "in its words"
    found << "#{locale}: the store page's description (sha256 #{sha256(live)}) differs from the repo (#{sha256(text)}) #{how}"
    found
  end
end
