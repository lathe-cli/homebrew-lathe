require "digest"
require "json"
require "open3"
require "optparse"
require "tempfile"
require "tmpdir"

module FormulaUpdater
  DEFAULT_FORMULA = "Formula/lathe.rb"
  DEFAULT_REPO = "lathe-cli/lathe"
  EXPECTED_PACKAGE = "lathe"
  TARGETS = %w[darwin_arm64 darwin_amd64 linux_arm64 linux_amd64].freeze
  STABLE_VERSION_RE = /\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/
  STABLE_TAG_RE = /\Av(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z/
  SHA256_RE = /\A[0-9a-f]{64}\z/

  Error = Class.new(StandardError)

  module_function

  def semver_tuple(version)
    match = STABLE_VERSION_RE.match(version)
    raise Error, "Version #{version} is not a stable SemVer release." unless match

    match.captures.map(&:to_i)
  end

  def check_ruby_syntax!(text, label)
    Tempfile.create(["lathe-formula", ".rb"]) do |tmp|
      tmp.write(text)
      tmp.flush
      _, stderr, status = Open3.capture3("ruby", "-c", tmp.path)
      raise Error, "Ruby syntax check failed for #{label}: #{stderr.strip}" unless status.success?
    end
  end

  def target_block_regex(repo, target)
    expected_url = "https://github.com/#{repo}/releases/download/v\#{version}/lathe_\#{version}_#{target}.tar.gz"
    /^(\s*url\s+"#{Regexp.escape(expected_url)}"\s*\n\s*sha256\s+")([0-9a-f]{64})("\s*)$/
  end

  def validate_formula_text!(text, repo:, label:)
    check_ruby_syntax!(text, label)

    versions = text.scan(/^\s*version\s+"([^"]+)"\s*$/).flatten
    raise Error, "Formula #{label} must declare exactly one version line." unless versions.length == 1

    current_version = versions[0]
    semver_tuple(current_version)

    url_count = text.scan(/^\s*url\s+"/).length
    sha_count = text.scan(/^\s*sha256\s+"/).length
    if url_count != TARGETS.length || sha_count != TARGETS.length
      raise Error, "Formula #{label} must define exactly #{TARGETS.length} url and sha256 entries."
    end

    TARGETS.each do |target|
      matches = text.scan(target_block_regex(repo, target))
      raise Error, "Formula #{label} is missing a valid interpolated url and sha256 block for #{target}." unless matches.length == 1
    end

    unless text.match?(/^\s*test\s+do\b[\s\S]*?#\{bin\}\/lathe version[\s\S]*?^\s*end\s*$/)
      raise Error, "Formula #{label} must verify lathe version inside test do."
    end

    current_version
  end

  def validate_formula_file!(path, repo:)
    raise Error, "Formula file does not exist: #{path}." unless File.file?(path)

    text = File.read(path, encoding: "UTF-8")
    validate_formula_text!(text, repo: repo, label: path)
  end

  def run_gh!(args)
    stdout, stderr, status = Open3.capture3("gh", *args)
    raise Error, "Command gh #{args.join(" ")} failed: #{stderr.strip}" unless status.success?

    stdout
  end

  def gh_json!(endpoint)
    JSON.parse(run_gh!(["api", endpoint]))
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON from gh api #{endpoint}: #{e.message}"
  end

  def resolve_release(repo:, raw_version:, raw_tag:)
    ver_input = raw_version.to_s.strip
    tag_input = raw_tag.to_s.strip

    if ver_input == "latest" && tag_input.empty?
      releases = gh_json!("repos/#{repo}/releases?per_page=100")
      stable = []
      if releases.is_a?(Array)
        stable = releases.select do |rel|
          rel.is_a?(Hash) &&
            rel["draft"] == false &&
            rel["prerelease"] == false &&
            STABLE_TAG_RE.match?(rel["tag_name"].to_s)
        end
      end
      selected = stable.max_by { |rel| semver_tuple(rel["tag_name"].delete_prefix("v")) }
      if selected.nil?
        latest = gh_json!("repos/#{repo}/releases/latest")
        if latest.is_a?(Hash) &&
           latest["draft"] == false &&
           latest["prerelease"] == false &&
           STABLE_TAG_RE.match?(latest["tag_name"].to_s)
          selected = latest
        end
      end
      raise Error, "No stable release was found for #{repo}." if selected.nil?

      tag = selected.fetch("tag_name")
      return [tag.delete_prefix("v"), tag, selected]
    end

    candidate = ver_input.empty? ? tag_input : ver_input
    raise Error, "Release version cannot be empty." if candidate.empty?

    normalized = candidate.start_with?("v") ? candidate.delete_prefix("v") : candidate
    raise Error, "Version #{candidate} is not a stable SemVer release." unless STABLE_VERSION_RE.match?(normalized)

    tag = "v#{normalized}"
    if !tag_input.empty? && tag_input != tag
      raise Error, "Payload tag #{tag_input} does not match version #{normalized}."
    end

    release = gh_json!("repos/#{repo}/releases/tags/#{tag}")
    raise Error, "Release #{tag} returned unexpected tag #{release["tag_name"]}." unless release["tag_name"] == tag
    raise Error, "Draft release #{tag} is rejected." if release["draft"] == true
    raise Error, "Prerelease #{tag} is rejected." if release["prerelease"] == true

    [normalized, tag, release]
  end

  def parse_checksums(path)
    sums = {}
    File.readlines(path, chomp: true).each do |line|
      next if line.strip.empty?

      match = line.match(/\A([0-9a-f]{64})[ \t]+\*?([^\s]+)\z/)
      raise Error, "Invalid checksum line in #{File.basename(path)}: #{line}" unless match

      digest, name = match.captures
      raise Error, "Duplicate conflicting checksum for #{name} in #{File.basename(path)}." if sums.key?(name) && sums[name] != digest

      sums[name] = digest
    end
    sums
  end

  def verify_release_assets!(repo:, tag:, version:, release:)
    assets = release["assets"]
    raise Error, "Release #{tag} has no assets list." unless assets.is_a?(Array)

    by_name = {}
    assets.each do |asset|
      next unless asset.is_a?(Hash) && asset["name"].is_a?(String)

      by_name[asset["name"]] = asset
    end

    checksums_name = "lathe_#{version}_checksums.txt"
    required_targets = TARGETS.map { |target| [target, "lathe_#{version}_#{target}.tar.gz"] }
    required_names = [checksums_name] + required_targets.map { |_, name| name }

    required_names.each do |name|
      raise Error, "Missing release asset #{name} in #{tag}." unless by_name.key?(name)
    end

    Dir.mktmpdir("lathe-release-") do |tmpdir|
      download_args = ["release", "download", tag, "--repo", repo, "--dir", tmpdir, "--clobber"]
      required_names.each do |name|
        download_args << "--pattern" << name
      end
      run_gh!(download_args)

      checksums_path = File.join(tmpdir, checksums_name)
      raise Error, "Downloaded checksum file #{checksums_name} is missing or empty." unless File.file?(checksums_path) && File.size(checksums_path) > 0

      sums = parse_checksums(checksums_path)
      verified = {}

      required_targets.each do |target, filename|
        txt_sha = sums[filename]
        raise Error, "Missing valid SHA256 for #{filename} in #{checksums_name}." unless txt_sha && SHA256_RE.match?(txt_sha)

        api_digest = by_name[filename]["digest"]
        if !api_digest.nil? && !api_digest.to_s.empty?
          digest_match = api_digest.to_s.match(/\Asha256:([0-9a-f]{64})\z/)
          raise Error, "Invalid GitHub asset digest for #{filename}: #{api_digest}." unless digest_match
          raise Error, "Checksum mismatch between #{checksums_name} and GitHub asset digest for #{filename}." unless digest_match[1] == txt_sha
        end

        archive_path = File.join(tmpdir, filename)
        raise Error, "Downloaded archive #{filename} is missing or empty." unless File.file?(archive_path) && File.size(archive_path) > 0

        actual_sha = Digest::SHA256.file(archive_path).hexdigest
        raise Error, "Checksum mismatch for downloaded archive #{filename}: expected #{txt_sha}, got #{actual_sha}." unless actual_sha == txt_sha

        verified[target] = actual_sha
      end

      verified
    end
  end

  def render_formula(current_text, target_version:, verified_checksums:, repo:)
    updated = current_text.dup
    version_count = 0
    updated.gsub!(/^(\s*version\s+")([^"]+)("\s*)$/) do
      version_count += 1
      "#{Regexp.last_match(1)}#{target_version}#{Regexp.last_match(3)}"
    end
    raise Error, "Expected one version declaration in formula, replaced #{version_count}." unless version_count == 1

    TARGETS.each do |target|
      block_count = 0
      updated.gsub!(target_block_regex(repo, target)) do
        block_count += 1
        "#{Regexp.last_match(1)}#{verified_checksums.fetch(target)}#{Regexp.last_match(3)}"
      end
      raise Error, "Expected one #{target} block in formula, replaced #{block_count}." unless block_count == 1
    end

    validate_formula_text!(updated, repo: repo, label: "rendered formula")
    updated
  end

  def write_github_output(path, values)
    return if path.nil? || path.empty?

    File.open(path, "a", encoding: "UTF-8") do |handle|
      values.each do |key, value|
        handle.puts("#{key}=#{value}")
      end
    end
  end

  def run(argv)
    options = {
      formula: DEFAULT_FORMULA,
      repo: DEFAULT_REPO,
      version: "latest",
      tag: "",
      package: "",
      validate: false,
      dry_run: false,
      github_output: ""
    }

    OptionParser.new do |parser|
      parser.banner = "Usage: ruby scripts/update-formula.rb [options]"
      parser.on("--formula PATH", "Formula path") { |value| options[:formula] = value }
      parser.on("--repo OWNER/REPO", "Upstream GitHub repository") { |value| options[:repo] = value }
      parser.on("--version VERSION", "Target version, tag, or latest") { |value| options[:version] = value }
      parser.on("--tag TAG", "Optional dispatch tag to check against version") { |value| options[:tag] = value }
      parser.on("--package NAME", "Optional dispatch package name") { |value| options[:package] = value }
      parser.on("--validate", "Validate formula syntax and invariants without network calls") { options[:validate] = true }
      parser.on("--dry-run", "Verify release and render changes without writing the formula file") { options[:dry_run] = true }
      parser.on("--github-output PATH", "Append step outputs to PATH") { |value| options[:github_output] = value }
    end.parse!(argv)

    package = options[:package].to_s.strip
    if !package.empty? && package != EXPECTED_PACKAGE
      raise Error, "Unexpected package payload: #{package}."
    end

    if options[:validate]
      current_version = validate_formula_file!(options[:formula], repo: options[:repo])
      puts "Formula #{options[:formula]} passed validation at version #{current_version}."
      return 0
    end

    current_version = validate_formula_file!(options[:formula], repo: options[:repo])
    current_text = File.read(options[:formula], encoding: "UTF-8")

    target_version, target_tag, release = resolve_release(
      repo: options[:repo],
      raw_version: options[:version],
      raw_tag: options[:tag]
    )

    if (semver_tuple(target_version) <=> semver_tuple(current_version)) < 0
      raise Error, "Downgrade from #{current_version} to #{target_version} is rejected."
    end

    verified = verify_release_assets!(
      repo: options[:repo],
      tag: target_tag,
      version: target_version,
      release: release
    )

    rendered = render_formula(
      current_text,
      target_version: target_version,
      verified_checksums: verified,
      repo: options[:repo]
    )

    changed = rendered != current_text
    write_github_output(
      options[:github_output],
      "changed" => (changed && !options[:dry_run]).to_s,
      "version" => target_version,
      "tag" => target_tag
    )

    if !changed
      puts "Formula #{options[:formula]} is already current at #{target_version}."
      return 0
    end

    if options[:dry_run]
      puts "Dry run: would update #{options[:formula]} from #{current_version} to #{target_version}."
      return 0
    end

    File.write(options[:formula], rendered, encoding: "UTF-8")
    validate_formula_file!(options[:formula], repo: options[:repo])
    puts "Updated #{options[:formula]} from #{current_version} to #{target_version}."
    0
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit(FormulaUpdater.run(ARGV))
  rescue FormulaUpdater::Error, OptionParser::ParseError => e
    warn "error: #{e.message}"
    exit(1)
  end
end
