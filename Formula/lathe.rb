class Lathe < Formula
  desc "Generate agent-friendly Cobra CLIs from API specs"
  homepage "https://github.com/lathe-cli/lathe"
  version "0.6.0"
  license "Apache-2.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v0.6.0/lathe_0.6.0_darwin_arm64.tar.gz"
      sha256 "c101ff43a2bb1aa63d6250069dcd5a5be82d7dea8bd842350aab1dffe72813d1"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v0.6.0/lathe_0.6.0_darwin_amd64.tar.gz"
      sha256 "511f5af3667e8bcafc0a40ff843d8100496a58b894289d1e8f8d9384e495bac5"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v0.6.0/lathe_0.6.0_linux_arm64.tar.gz"
      sha256 "08da7f3d1974b2e67f32e6a2945fefb407854bd8fb754451c7db7914d3cb9606"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v0.6.0/lathe_0.6.0_linux_amd64.tar.gz"
      sha256 "8dc8e9f310ac7af1c8cec45b7ddf905092815abcba379fb0bffcaff960d17856"
    end
  end

  def install
    bin.install "lathe"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lathe version")
  end
end
