# frozen_string_literal: true

# Run: cd app && bundle exec ruby fastlane/test/play_listing_test.rb (scripts/gates/fastlane.sh).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../play_listing"

class PlayListingTest < Minitest::Test
  Release = PlayListing::Release
  Listing = Struct.new(:title, :short_description, :full_description, :video)

  # Supply::Client's edit methods; records the calls and keeps the listing Play would hold.
  class FakePlay
    attr_reader :calls, :committed

    def initialize(listings: {})
      @listings = listings
      @staged = {}
      @committed = {}
      @calls = []
    end

    def listing_for_language(locale)
      @calls << [:listing_for_language, locale]
      @listings.fetch(locale) { Listing.new }
    end

    def update_listing_for_language(language:, title:, short_description:, full_description:, video:)
      @calls << [:update_listing_for_language, language]
      @staged[language] = Listing.new(title, short_description, full_description, video)
    end

    def validate_current_edit!
      @calls << [:validate]
    end

    def commit_current_edit!
      @calls << [:commit]
      @committed = @staged
    end

    def abort_current_edit
      @calls << [:abort]
    end
  end

  STAGED = File.expand_path("../metadata/android", __dir__)
  # Play's states for 1541: held by managed publishing since 25 Nov 2026, published on launch day.
  HELD = [Release.new("APPROVED_NOT_PUBLISHED", ["1541"])].freeze
  LIVE = [Release.new("PUBLISHED", ["1541"])].freeze
  DEC1 = Time.new(2026, 12, 1, 0, 0, 0, "+01:00")
  NOV30_LATE = Time.new(2026, 11, 30, 23, 59, 0, "+01:00")
  WORKFLOW = File.expand_path("../../../.github/workflows/play-listing.yml", __dir__)

  def setup
    @log = []
  end

  def write_listing(dir, locale, title: "Snacklist", short: "Kurz", full: "Lang\n\nZweiter Absatz")
    FileUtils.mkdir_p(File.join(dir, locale))
    { "title" => title, "short_description" => short, "full_description" => full }.each do |field, text|
      File.write(File.join(dir, locale, "#{field}.txt"), "#{text}\n")
    end
  end

  # The lane's flow: the gate on production, then the edit, then the read-back edit on upload.
  def run_lane(upload:, plays:, production: LIVE, held: false, now: DEC1, version_code: "1541",
               texts: { "de-DE" => fields }, held_from: DEC1)
    queue = plays.dup
    PlayListing.run(texts: texts, upload: upload, version_code: version_code, production_releases: production,
                    new_client: -> { queue.shift or flunk("no edit left") }, log: @log.method(:push),
                    with_held_release: held, held_from: held_from, now: now)
    queue
  end

  def blockers(production, held:, now: DEC1, version_code: "1541")
    PlayListing.blockers(production_releases: production, version_code: version_code, with_held_release: held,
                         held_from: DEC1, now: now)
  end

  def same_listing = FakePlay.new(listings: { "de-DE" => Listing.new("Snacklist", "Kurz", "Neu", nil) })

  def fields(full = "Neu")
    { "title" => "Snacklist", "short_description" => "Kurz", "full_description" => full }
  end

  def test_the_staged_repo_listing_loads_within_plays_limits
    texts = PlayListing.load(STAGED)
    assert_equal %w[de-DE en-US], texts.keys
    texts.each_value do |f|
      PlayListing::LIMITS.each { |field, max| assert_operator f.fetch(field).length, :<=, max }
    end
    refute_includes texts["de-DE"]["full_description"], PlayListing::LK1_SENTENCE
  end

  def test_the_field_is_the_file_without_its_trailing_newline
    Dir.mktmpdir do |dir|
      write_listing(dir, "de-DE")
      text = PlayListing.load(dir)["de-DE"]["full_description"]
      assert_equal "Lang\n\nZweiter Absatz", text
      assert_equal Digest::SHA256.hexdigest("Lang\n\nZweiter Absatz"), PlayListing.sha256(text)
    end
  end

  def test_a_text_over_plays_limit_refuses
    Dir.mktmpdir do |dir|
      write_listing(dir, "de-DE", title: "x" * 31, full: "ä" * 4001)
      error = assert_raises(PlayListing::Refused) { PlayListing.load(dir) }
      assert_match "de-DE/title: 31 > 30", error.message
      assert_match "de-DE/full_description: 4001 > 4000", error.message
    end
  end

  def test_images_or_other_files_in_a_locale_refuse
    Dir.mktmpdir do |dir|
      write_listing(dir, "en-US")
      FileUtils.mkdir_p(File.join(dir, "en-US", "images", "phoneScreenshots"))
      File.write(File.join(dir, "en-US", "video.txt"), "https://example.com\n")
      error = assert_raises(PlayListing::Refused) { PlayListing.load(dir) }
      assert_match "en-US: images, video.txt not allowed", error.message
    end
  end

  def test_a_missing_field_or_multi_line_title_refuses
    Dir.mktmpdir do |dir|
      write_listing(dir, "de-DE", title: "Zwei\nZeilen")
      File.delete(File.join(dir, "de-DE", "short_description.txt"))
      error = assert_raises(PlayListing::Refused) { PlayListing.load(dir) }
      assert_match "de-DE: short_description.txt missing", error.message
      assert_match "de-DE/title: must be one line", error.message
    end
  end

  def test_production_releases_parse_plays_releases_endpoint
    require "google/apis/androidpublisher_v3"
    api = Google::Apis::AndroidpublisherV3
    summary = api::ReleaseSummary.new(release_lifecycle_state: "RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED",
                                      release_name: "1541 (1.0.0)",
                                      active_artifacts: [api::ArtifactSummary.new(version_code: 1541)])
    service = Object.new
    service.define_singleton_method(:list_application_track_releases) do |parent|
      raise "asked for #{parent}" unless parent == "applications/com.snacklist.app/tracks/production"

      api::ListReleaseSummariesResponse.new(releases: [summary])
    end
    assert_equal HELD, PlayListing.production_releases(service, "com.snacklist.app")
  end

  def test_upload_while_the_release_is_held_opens_no_edit_without_the_held_path
    # 26 Nov 2026: 1541 approved in production, held by managed publishing.
    error = assert_raises(PlayListing::Refused) { run_lane(upload: true, plays: [], production: HELD) }
    assert_match "production 1541 is APPROVED_NOT_PUBLISHED, not PUBLISHED yet", error.message
  end

  def test_an_upload_needs_the_named_build_in_a_usable_state
    assert_equal ["PLAY_PUBLISHED_VERSION_CODE is not set to the production build"], blockers(LIVE, held: false, version_code: "")
    assert_equal ["production has no release with versionCode 1557"], blockers(LIVE, held: true, version_code: "1557")
    %w[IN_REVIEW NOT_APPROVED DRAFT].each do |state|
      other = [Release.new(state, ["1541"])]
      assert_match "is #{state}, not PUBLISHED", blockers(other, held: false).join
      assert_match "is #{state}, not held by managed publishing", blockers(other, held: true).join
    end
  end

  def test_the_held_path_needs_the_release_still_held_and_launch_day
    assert_empty blockers(HELD, held: true)
    assert_match "only from 2026-12-01T00:00:00+01:00", blockers(HELD, held: true, now: NOV30_LATE).join
    assert_match "is PUBLISHED, not held", blockers(LIVE, held: true).join
    assert_equal ["PLAY_LISTING_HELD_FROM is not set"],
                 PlayListing.blockers(production_releases: HELD, version_code: "1541", with_held_release: true,
                                      held_from: nil, now: DEC1)
  end

  def test_joining_the_held_release_before_launch_day_opens_no_edit
    error = assert_raises(PlayListing::Refused) do
      run_lane(upload: true, plays: [], production: HELD, held: true, now: NOV30_LATE)
    end
    assert_match "only from 2026-12-01T00:00:00+01:00 (Peter K1)", error.message
  end

  def test_from_launch_day_the_listing_joins_the_held_release_and_reads_back
    play = FakePlay.new
    check = same_listing
    assert_empty run_lane(upload: true, plays: [play, check], production: HELD, held: true)
    assert_equal [:commit], play.calls.last
    assert_equal "Neu", play.committed["de-DE"].full_description
    assert_equal [[:listing_for_language, "de-DE"], [:abort]], check.calls
    assert_includes @log, "Production releases: APPROVED_NOT_PUBLISHED 1541"
  end

  def test_a_held_from_before_launch_day_refuses_and_opens_no_edit
    # A typo in the dispatch: 1 Nov instead of 1 Dec. Only the date gate stands, and it holds.
    typo = Time.new(2026, 11, 1, 0, 0, 0, "+01:00")
    [typo, DEC1 - 1].each do |held_from|
      error = assert_raises(PlayListing::Refused) do
        run_lane(upload: true, plays: [], production: HELD, held: true, now: DEC1 + 3600, held_from: held_from)
      end
      assert_match "is before launch day 2026-12-01T00:00:00+01:00; it may only move the date later", error.message
    end
  end

  def test_held_from_may_move_launch_day_later_only
    later = Time.new(2026, 12, 2, 9, 0, 0, "+01:00")
    assert_empty PlayListing.blockers(production_releases: HELD, version_code: "1541", with_held_release: true,
                                      held_from: Time.iso8601("2026-11-30T23:00:00Z"), now: DEC1)
    assert_match "only from 2026-12-02T09:00:00+01:00",
                 PlayListing.blockers(production_releases: HELD, version_code: "1541", with_held_release: true,
                                      held_from: later, now: DEC1).join
    play = FakePlay.new
    assert_empty run_lane(upload: true, plays: [play, same_listing], production: HELD, held: true, now: later,
                          held_from: later)
    assert_equal [:commit], play.calls.last
  end

  # Play's answer, as supply's call_google_api raises it without its rescue.
  NOT_SENT = "Google Api Error: badRequest: Changes cannot be sent for review automatically. Please set the query " \
             "parameter changesNotSentForReview to true. Once committed, the changes in this edit can be sent for " \
             "review from the Google Play Console UI."

  def test_a_commit_play_will_not_send_for_review_fails_the_run_and_tells_ops_to_send_it
    play = FakePlay.new
    def play.commit_current_edit!
      @calls << [:commit]
      raise NOT_SENT
    end
    def play.commit_not_sent_for_review!
      @calls << [:commit_not_sent_for_review]
      @committed = @staged
    end
    error = assert_raises(PlayListing::Refused) { run_lane(upload: true, plays: [play, same_listing]) }
    assert_match "NOT SENT FOR REVIEW", error.message
    assert_match "Send changes for review", error.message
    assert_equal [[:commit], [:commit_not_sent_for_review]], play.calls.last(2)
    refute_includes play.calls, [:abort]
    assert_equal "Neu", play.committed["de-DE"].full_description
    assert(@log.any? { |l| l.start_with?("!!! NOT SENT FOR REVIEW !!!") })
  end

  def test_supply_commit_sets_changes_not_sent_for_review_for_that_commit_only
    require "supply"
    Supply.config = FastlaneCore::Configuration.create(Supply::Options.available_options, { package_name: "app" })
    client = Object.new
    seen = nil
    client.define_singleton_method(:commit_current_edit!) { seen = Supply.config[:changes_not_sent_for_review] }
    client.extend(PlayListing::SupplyCommit).commit_not_sent_for_review!
    assert seen
    refute Supply.config[:changes_not_sent_for_review]
  end

  def test_validate_runs_any_day_and_never_commits
    [[HELD, NOV30_LATE], [LIVE, DEC1]].each do |production, now|
      play = FakePlay.new(listings: { "de-DE" => Listing.new("Alt", "Alt", "Alt", "https://youtu.be/x") })
      spare = FakePlay.new
      assert_equal [spare], run_lane(upload: false, plays: [play, spare], production: production, now: now)
      assert_equal [[:validate], [:abort]], play.calls.last(2)
      refute_includes play.calls, [:commit]
      assert_empty spare.calls
    end
    assert(@log.any? { |l| l.include?("An upload now would refuse: production 1541 is APPROVED_NOT_PUBLISHED") })
  end

  def test_upload_after_publishing_commits_every_locale_and_keeps_the_video
    play = FakePlay.new(listings: { "de-DE" => Listing.new("Alt", "Alt", "Alt", "https://youtu.be/x") })
    check = FakePlay.new(listings: { "de-DE" => Listing.new("Snacklist", "Kurz", "Neu de", nil),
                                     "en-US" => Listing.new("Snacklist", "Kurz", "New en", nil) })
    run_lane(upload: true, plays: [play, check], texts: { "de-DE" => fields("Neu de"), "en-US" => fields("New en") })
    assert_equal [:commit], play.calls.last
    refute_includes play.calls, [:abort]
    assert_equal "Neu de", play.committed["de-DE"].full_description
    assert_equal "https://youtu.be/x", play.committed["de-DE"].video
    assert_equal "New en", play.committed["en-US"].full_description
  end

  def test_a_failing_play_call_deletes_the_edit
    play = FakePlay.new
    def play.commit_current_edit! = raise("Play said no")
    assert_raises(RuntimeError) { run_lane(upload: true, plays: [play]) }
    assert_equal [:abort], play.calls.last
  end

  def test_a_failure_after_the_commit_is_reported_and_not_committed_twice
    play = FakePlay.new
    def play.commit_current_edit!
      super
      raise "network dropped after the commit"
    end
    def play.abort_current_edit
      super
      raise "no active edit"
    end
    assert_raises(RuntimeError) { run_lane(upload: true, plays: [play]) }
    assert_equal 1, play.calls.count([:commit])
    assert(@log.any? { |l| l.include?("Could not delete the edit (Play expires it): no active edit") })
  end

  def test_the_lane_fails_when_the_read_back_differs_and_says_it_committed
    stale = FakePlay.new(listings: { "de-DE" => Listing.new("Snacklist", "Kurz", "Alt", nil) })
    error = assert_raises(PlayListing::Refused) { run_lane(upload: true, plays: [FakePlay.new, stale]) }
    assert_match "The listing was committed, but Play's read-back differs", error.message
    assert_match "de-DE/full_description", error.message
  end

  def preflight(production, now:)
    PlayListing.preflight(production_releases: production, version_code: "1541", held_from: DEC1, now: now,
                          log: @log.method(:push))
  end

  def test_preflight_before_launch_day_shows_the_held_path_opens_on_dec_1
    preflight(HELD, now: NOV30_LATE)
    assert_includes @log, "Production releases: APPROVED_NOT_PUBLISHED 1541"
    assert_includes @log, "Held-release path: the listing may join the held release only from 2026-12-01T00:00:00+01:00 (Peter K1)"
    assert_includes @log, "After-publish path: production 1541 is APPROVED_NOT_PUBLISHED, not PUBLISHED yet"
    preflight(LIVE, now: NOV30_LATE)
  end

  def test_preflight_fails_when_neither_path_can_use_the_build
    [[], [Release.new("IN_REVIEW", ["1541"])], [Release.new("APPROVED_NOT_PUBLISHED", ["1557"])]].each do |production|
      assert_raises(PlayListing::Refused) { preflight(production, now: NOV30_LATE) }
    end
  end

  def test_the_workflow_maps_each_mode_to_the_lane_and_its_switches
    workflow = YAML.safe_load_file(WORKFLOW)
    inputs = workflow.fetch(true).fetch("workflow_dispatch").fetch("inputs")
    assert_equal %w[validate upload check preflight], inputs.fetch("mode").fetch("options")
    assert_equal "validate", inputs.fetch("mode").fetch("default")
    assert_equal false, inputs.fetch("with_held_release").fetch("default")
    assert_equal DEC1, Time.iso8601(inputs.fetch("held_release_from").fetch("default"))
    run = workflow.fetch("jobs").fetch("listing").fetch("steps").find { |step| step["run"]&.include?("fastlane android") }
    assert_equal({ "LANE" => "${{ inputs.mode == 'check' && 'listing_check' || inputs.mode == 'preflight' && 'listing_preflight' || 'listing' }}",
                   "RELEASE_UPLOAD" => "${{ inputs.mode == 'upload' }}",
                   "PLAY_PUBLISHED_VERSION_CODE" => "${{ inputs.published_version_code }}",
                   "PLAY_LISTING_WITH_HELD_RELEASE" => "${{ inputs.with_held_release }}",
                   "PLAY_LISTING_HELD_FROM" => "${{ inputs.held_release_from }}" }, run.fetch("env"))
  end

  def test_read_back_names_each_field_that_differs
    texts = { "de-DE" => fields("Neu") }
    same = FakePlay.new(listings: { "de-DE" => Listing.new("Snacklist", "Kurz", "Neu", nil) })
    assert_empty PlayListing.read_back(client: same, texts: texts, log: @log.method(:push))
    assert_equal [:abort], same.calls.last

    old = FakePlay.new(listings: { "de-DE" => Listing.new("Snacklist", "Kurz", "Neu\n", nil) })
    mismatches = PlayListing.read_back(client: old, texts: texts, log: @log.method(:push))
    assert_equal 1, mismatches.size
    assert_match "de-DE/full_description: Play has sha256 #{Digest::SHA256.hexdigest("Neu\n")}", mismatches.first
  end

  def test_the_public_page_check_compares_the_rendered_description_exactly
    text = "Snacklist ist die Einkaufsliste.\n\n• Eine Liste & mehr"
    html = '<div data-g-id="description" inert>Snacklist ist die Einkaufsliste.<br><br>• Eine Liste &amp; mehr</div>'
    assert_equal text, PlayListing.public_description(html)
    assert_empty public_mismatches(200, html, text)
    assert_includes @log, "Store page de-DE/full_description: sha256 #{PlayListing.sha256(text)}, repo #{PlayListing.sha256(text)}"

    one_break = '<div data-g-id="description">Snacklist ist die Einkaufsliste.<br>• Eine Liste &amp; mehr</div>'
    assert_match "differs from the repo (#{PlayListing.sha256(text)}) only in whitespace", public_mismatches(200, one_break, text).first

    old = "<div data-g-id=\"description\">Snacklist.<br><br>#{PlayListing::LK1_SENTENCE}</div>"
    found = public_mismatches(200, old, text)
    assert(found.any? { |l| l.include?("Legal LK1") })
    assert(found.any? { |l| l.include?("in its words") })
    assert_equal ["de-DE: the Play store page answers 404"], public_mismatches(404, "", text)
  end

  def public_mismatches(status, html, text)
    PlayListing.public_mismatches(locale: "de-DE", status: status, html: html, text: text, log: @log.method(:push))
  end

  def test_the_store_page_is_the_locales_language
    assert_equal "https://play.google.com/store/apps/details?id=com.snacklist.app&hl=de&gl=DE",
                 PlayListing.store_page_url("com.snacklist.app")
    assert_match "hl=en&gl=US", PlayListing.store_page_url("com.snacklist.app", "en-US")
  end
end
