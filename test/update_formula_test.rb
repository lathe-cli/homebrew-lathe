require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
UPDATER = File.join(REPO_ROOT, "scripts", "update-formula.rb")
REAL_FORMULA = File.join(REPO_ROOT, "Formula", "lathe.rb")
TARGETS = %w[darwin_arm64 darwin_amd64 linux_arm64 linux_amd64].freeze

def assert(condition, message)
  raise message unless condition
end

def run_updater(args, stub_bin: nil)
  env = {}
  env["PATH"] = stub_bin ? "#{stub_bin}:#{ENV.fetch("PATH")}" : ENV.fetch("PATH")
  Open3.capture3(env, "ruby", UPDATER, *args)
end

def write_stub_gh(stub_bin, state_dir)
  gh_path = File.join(stub_bin, "gh")
  script = <<~RUBY
    #!/usr/bin/env ruby
    require "fileutils"
    require "json"

    state_dir = #{state_dir.inspect}
    if ARGV[0] == "api"
      endpoint = ARGV[1]
      case endpoint
      when %r{\\Arepos/lathe-cli/lathe/releases\\?per_page=100\\z}
        puts File.read(File.join(state_dir, "releases.json"))
        exit 0
      when %r{\\Arepos/lathe-cli/lathe/releases/tags/([^/]+)\\z}
        tag = Regexp.last_match(1)
        releases = JSON.parse(File.read(File.join(state_dir, "releases.json")))
        match = releases.find { |r| r["tag_name"] == tag }
        if match
          puts JSON.generate(match)
          exit 0
        end
        warn "release not found: \#{tag}"
        exit 1
      else
        warn "unexpected endpoint: \#{endpoint}"
        exit 1
      end
    elsif ARGV[0] == "release" && ARGV[1] == "download"
      tag = ARGV[2]
      dir = "."
      patterns = []
      i = 3
      while i < ARGV.length
        case ARGV[i]
        when "--dir"
          dir = ARGV[i + 1]
          i += 2
        when "--pattern"
          patterns << ARGV[i + 1]
          i += 2
        when "--repo"
          i += 2
        else
          i += 1
        end
      end
      src_dir = File.join(state_dir, "assets", tag)
      patterns.each do |pattern|
        src = File.join(src_dir, pattern)
        unless File.file?(src)
          warn "missing stub asset: \#{src}"
          exit 1
        end
        FileUtils.cp(src, File.join(dir, pattern))
      end
      exit 0
    else
      warn "unexpected gh invocation: \#{ARGV.join(" ")}"
      exit 1
    end
  RUBY
  File.write(gh_path, script)
  File.chmod(0o755, gh_path)
end

def build_release_fixture(state_dir, version, prerelease: false, draft: false, tamper_checksum_txt: false, tamper_api_digest: false, tamper_archive: false)
  tag = "v#{version}"
  asset_dir = File.join(state_dir, "assets", tag)
  FileUtils.mkdir_p(asset_dir)

  checksum_lines = []
  assets = []

  TARGETS.each do |target|
    filename = "lathe_#{version}_#{target}.tar.gz"
    content = "lathe-#{version}-#{target}-binary-archive"
    path = File.join(asset_dir, filename)
    File.write(path, content)
    sha = Digest::SHA256.file(path).hexdigest
    File.write(path, "#{content}-corrupted") if tamper_archive && target == "darwin_amd64"
    listed_sha = tamper_checksum_txt && target == "darwin_arm64" ? ("0" * 64) : sha
    api_sha = tamper_api_digest && target == "linux_amd64" ? ("f" * 64) : sha
    checksum_lines << "#{listed_sha}  #{filename}"
    assets << { "name" => filename, "digest" => tamper_archive ? nil : "sha256:#{api_sha}" }
  end

  checksums_name = "lathe_#{version}_checksums.txt"
  checksums_path = File.join(asset_dir, checksums_name)
  File.write(checksums_path, checksum_lines.join("\n") + "\n")
  assets << { "name" => checksums_name, "digest" => "sha256:#{Digest::SHA256.file(checksums_path).hexdigest}" }

  {
    "tag_name" => tag,
    "draft" => draft,
    "prerelease" => prerelease,
    "assets" => assets
  }
end

def test_validate_real_formula
  stdout, stderr, status = run_updater(["--validate", "--formula", REAL_FORMULA])
  assert(status.success?, "real formula validation failed: #{stderr}")
  assert(stdout.include?("passed validation"), "unexpected validate output: #{stdout}")
end

def test_validate_rejects_bad_formulas
  Dir.mktmpdir("lathe-bad-formula-") do |dir|
    base = File.read(REAL_FORMULA)

    prerelease_formula = File.join(dir, "prerelease.rb")
    File.write(prerelease_formula, base.sub('version "0.6.5"', 'version "0.7.0-rc.2"'))
    _, stderr, status = run_updater(["--validate", "--formula", prerelease_formula])
    assert(!status.success?, "prerelease formula version should fail validation")
    assert(stderr.include?("stable SemVer"), "unexpected error: #{stderr}")

    hardcoded_formula = File.join(dir, "hardcoded.rb")
    File.write(hardcoded_formula, base.sub('v#{version}/lathe_#{version}_darwin_arm64', 'v0.6.5/lathe_0.6.5_darwin_arm64'))
    _, _, status = run_updater(["--validate", "--formula", hardcoded_formula])
    assert(!status.success?, "hardcoded URL version should fail validation")

    bad_sha_formula = File.join(dir, "bad_sha.rb")
    File.write(bad_sha_formula, base.sub("acfd96aeb582040e567b97b5c98701785bb71c441bd68f70bda4e829c8a5f29f", "deadbeef"))
    _, _, status = run_updater(["--validate", "--formula", bad_sha_formula])
    assert(!status.success?, "truncated sha256 should fail validation")
  end
end

def test_updater_with_stub_releases
  Dir.mktmpdir("lathe-updater-test-") do |dir|
    stub_bin = File.join(dir, "bin")
    state_dir = File.join(dir, "state")
    FileUtils.mkdir_p(stub_bin)
    FileUtils.mkdir_p(state_dir)
    write_stub_gh(stub_bin, state_dir)

    r_rc = build_release_fixture(state_dir, "0.7.0-rc.2", prerelease: true)
    r_fake_stable_flag = build_release_fixture(state_dir, "0.8.0-rc.1", prerelease: false)
    r_065 = build_release_fixture(state_dir, "0.6.5", prerelease: false)
    r_066_bad_txt = build_release_fixture(state_dir, "0.6.6", prerelease: false, tamper_checksum_txt: true)
    r_067_bad_api = build_release_fixture(state_dir, "0.6.7", prerelease: false, tamper_api_digest: true)
    r_068_prerelease_flag = build_release_fixture(state_dir, "0.6.8", prerelease: true)
    r_069_bad_archive = build_release_fixture(state_dir, "0.6.9", prerelease: false, tamper_archive: true)
    r_064 = build_release_fixture(state_dir, "0.6.4", prerelease: false)

    File.write(
      File.join(state_dir, "releases.json"),
      JSON.generate([r_rc, r_fake_stable_flag, r_065, r_064])
    )

    formula_path = File.join(dir, "lathe.rb")
    initial_formula = File.read(REAL_FORMULA).sub('version "0.6.5"', 'version "0.6.0"')
    File.write(formula_path, initial_formula)

    stdout, stderr, status = run_updater(["--formula", formula_path, "--version", "latest", "--dry-run"], stub_bin: stub_bin)
    assert(status.success?, "dry-run latest failed: #{stderr}")
    assert(stdout.include?("would update") && stdout.include?("0.6.5"), "dry-run did not select 0.6.5: #{stdout}")
    assert(File.read(formula_path) == initial_formula, "dry-run modified formula file")

    output_env = File.join(dir, "github_output.txt")
    stdout, stderr, status = run_updater(["--formula", formula_path, "--version", "latest", "--github-output", output_env], stub_bin: stub_bin)
    assert(status.success?, "latest update failed: #{stderr}")
    assert(stdout.include?("Updated") && stdout.include?("0.6.5"), "unexpected update output: #{stdout}")
    updated_text = File.read(formula_path)
    assert(updated_text.include?('version "0.6.5"'), "updated formula missing version 0.6.5")
    assert(updated_text.include?('v#{version}/lathe_#{version}_darwin_arm64.tar.gz'), "updated formula lost version interpolation")
    assert(File.read(output_env).include?("changed=true\n"), "github_output missing changed=true")

    stdout, stderr, status = run_updater(["--formula", formula_path, "--version", "v0.6.5"], stub_bin: stub_bin)
    assert(status.success?, "idempotent v0.6.5 run failed: #{stderr}")
    assert(stdout.include?("already current at 0.6.5"), "unexpected idempotent output: #{stdout}")

    ["v0.7.0-rc.2", "v0.1.0-fix.1", "v01.2.0", "v0.6.4"].each do |rejected|
      _, stderr, status = run_updater(["--formula", formula_path, "--version", rejected], stub_bin: stub_bin)
      assert(!status.success?, "expected #{rejected} to be rejected")
      assert(!stderr.empty?, "expected error message for #{rejected}")
    end

    File.write(
      File.join(state_dir, "releases.json"),
      JSON.generate([r_066_bad_txt, r_067_bad_api, r_068_prerelease_flag, r_069_bad_archive, r_065])
    )

    ["v0.6.6", "v0.6.7", "v0.6.8", "v0.6.9"].each do |rejected|
      _, stderr, status = run_updater(["--formula", formula_path, "--version", rejected], stub_bin: stub_bin)
      assert(!status.success?, "expected #{rejected} to be rejected")
      assert(!stderr.empty?, "expected error message for #{rejected}")
    end

    _, stderr, status = run_updater(["--formula", formula_path, "--version", "0.6.5", "--tag", "v0.6.4"], stub_bin: stub_bin)
    assert(!status.success?, "expected tag mismatch to be rejected")
    assert(stderr.include?("does not match"), "unexpected tag mismatch error: #{stderr}")

    _, stderr, status = run_updater(["--formula", formula_path, "--package", "other", "--version", "0.6.5"], stub_bin: stub_bin)
    assert(!status.success?, "expected unexpected package to be rejected")
    assert(stderr.include?("Unexpected package"), "unexpected package error: #{stderr}")

    assert(File.read(formula_path) == updated_text, "rejected runs modified formula file")
  end
end

test_validate_real_formula
test_validate_rejects_bad_formulas
test_updater_with_stub_releases
puts "All update-formula tests passed."
