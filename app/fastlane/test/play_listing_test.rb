# frozen_string_literal: true

# Run: cd app && bundle exec ruby fastlane/test/play_listing_test.rb (scripts/gates/fastlane.sh).
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../play_listing"

class PlayListingTest < Minitest::Test
  Release = Struct.new(:status, :version_codes)
  Listing = Struct.new(:title, :short_description, :full_description, :video)

  # Supply::Client's edit methods; records the calls and keeps the listing Play would hold.
  class FakePlay
    attr_reader :calls, :committed

    def initialize(production: [], listings: {})
      @production = production
      @listings = listings
      @staged = {}
      @committed = {}
      @calls = []
    end

    def tracks(*names)
      @calls << [:tracks, names]
      [Struct.new(:track, :releases).new("production", @production)]
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
  PUBLISHED = [Release.new("completed", ["1541"])].freeze

  def setup
    @log = []
  end

  def write_listing(dir, locale, title: "Snacklist", short: "Kurz", full: "Lang\n\nZweiter Absatz")
    FileUtils.mkdir_p(File.join(dir, locale))
    { "title" => title, "short_description" => short, "full_description" => full }.each do |field, text|
      File.write(File.join(dir, locale, "#{field}.txt"), "#{text}\n")
    end
  end

  def publish(play, upload:, status: 200, version_code: "1541", texts: { "de-DE" => fields })
    PlayListing.publish(client: play, texts: texts, upload: upload, store_page_status: status,
                        version_code: version_code, log: @log.method(:push))
  end

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

  def test_upload_before_the_production_release_is_published_changes_nothing
    # 26 Nov 2026: 1541 approved in production but held by managed publishing; the page is 404.
    play = FakePlay.new(production: PUBLISHED)
    error = assert_raises(PlayListing::Refused) { publish(play, upload: true, status: 404) }
    assert_match "store page answers 404", error.message
    assert_equal [[:tracks, ["production"]], [:abort]], play.calls
    assert_empty play.committed
  end

  def test_upload_needs_the_published_build_on_production
    [["", "PLAY_PUBLISHED_VERSION_CODE is not set"], ["1557", "no completed release with versionCode 1557"]].each do |code, reason|
      play = FakePlay.new(production: PUBLISHED)
      error = assert_raises(PlayListing::Refused) { publish(play, upload: true, version_code: code) }
      assert_match reason, error.message
      refute_includes play.calls, [:commit]
    end
    halted = FakePlay.new(production: [Release.new("halted", ["1541"])])
    assert_raises(PlayListing::Refused) { publish(halted, upload: true) }
    refute_includes halted.calls, [:commit]
  end

  def test_validate_only_runs_any_day_and_deletes_the_edit
    play = FakePlay.new(listings: { "de-DE" => Listing.new("Alt", "Alt", "Alt", "https://youtu.be/x") })
    publish(play, upload: false, status: 404, version_code: "")
    assert_equal [:validate], play.calls[-2]
    assert_equal [:abort], play.calls[-1]
    refute_includes play.calls, [:commit]
    assert(@log.any? { |l| l.include?("An upload now would refuse: the Play store page answers 404") })
  end

  def test_validate_never_commits_even_when_the_gate_is_open
    play = FakePlay.new(production: PUBLISHED)
    publish(play, upload: false)
    refute_includes play.calls, [:commit]
    assert_equal [[:validate], [:abort]], play.calls.last(2)
    assert_empty play.committed
  end

  def test_upload_after_publishing_commits_every_locale_and_keeps_the_video
    play = FakePlay.new(production: PUBLISHED,
                        listings: { "de-DE" => Listing.new("Alt", "Alt", "Alt", "https://youtu.be/x") })
    publish(play, upload: true, texts: { "de-DE" => fields("Neu de"), "en-US" => fields("New en") })
    assert_equal [:commit], play.calls.last
    refute_includes play.calls, [:abort]
    assert_equal "Neu de", play.committed["de-DE"].full_description
    assert_equal "https://youtu.be/x", play.committed["de-DE"].video
    assert_equal "New en", play.committed["en-US"].full_description
  end

  def test_a_failing_play_call_deletes_the_edit
    play = FakePlay.new(production: PUBLISHED)
    def play.commit_current_edit! = raise("Play said no")
    assert_raises(RuntimeError) { publish(play, upload: true) }
    assert_equal [:abort], play.calls.last
  end

  def test_a_failure_after_the_commit_is_reported_and_not_committed_twice
    play = FakePlay.new(production: PUBLISHED)
    def play.commit_current_edit!
      super
      raise "network dropped after the commit"
    end
    def play.abort_current_edit
      super
      raise "no active edit"
    end
    assert_raises(RuntimeError) { publish(play, upload: true) }
    assert_equal 1, play.calls.count([:commit])
    assert(@log.any? { |l| l.include?("Could not delete the edit (Play expires it): no active edit") })
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

  def test_the_public_page_check_reads_the_rendered_description
    text = "Snacklist ist die Einkaufsliste.\n\n• Eine Liste & mehr"
    html = '<div data-g-id="description" inert>Snacklist ist die Einkaufsliste.<br><br>• Eine Liste &amp; mehr</div>'
    assert_equal text, PlayListing.public_description(html)
    assert_empty PlayListing.public_mismatches(locale: "de-DE", status: 200, html: html, text: text)

    old = "<div data-g-id=\"description\">Snacklist.<br><br>#{PlayListing::LK1_SENTENCE}</div>"
    found = PlayListing.public_mismatches(locale: "de-DE", status: 200, html: old, text: text)
    assert(found.any? { |l| l.include?("Legal LK1") })
    assert_equal ["de-DE: the Play store page answers 404"],
                 PlayListing.public_mismatches(locale: "de-DE", status: 404, html: "", text: text)
  end

  def test_the_store_page_is_the_locales_language
    assert_equal "https://play.google.com/store/apps/details?id=com.snacklist.app&hl=de&gl=DE",
                 PlayListing.store_page_url("com.snacklist.app")
    assert_match "hl=en&gl=US", PlayListing.store_page_url("com.snacklist.app", "en-US")
  end
end
