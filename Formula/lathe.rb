class Lathe < Formula
  desc "Generate agent-friendly Cobra CLIs from API specs"
  homepage "https://github.com/lathe-cli/lathe"
  version "0.4.2"
  license "Apache-2.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v0.4.2/lathe_0.4.2_darwin_arm64.tar.gz"
      sha256 "ac60d9d1019b264e45f85a496530201dd519b6e96ab16d1f59546be017e9529e"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v0.4.2/lathe_0.4.2_darwin_amd64.tar.gz"
      sha256 "9f60973f1398dba5bfae76e63e2190f2462e57fda0af43edb2edd17ec3c55877"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v0.4.2/lathe_0.4.2_linux_arm64.tar.gz"
      sha256 "2ad22b2852681a9320a83cda7932c497d19d2d711f746bf693ea9cb6ee51083a"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v0.4.2/lathe_0.4.2_linux_amd64.tar.gz"
      sha256 "9abeccb4305bea8016852cac3fae36f4d3a5589f1c158fbed99981932458b236"
    end
  end

  def install
    bin.install "lathe"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lathe version")
  end
end