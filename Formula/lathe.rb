class Lathe < Formula
  desc "Generate agent-friendly Cobra CLIs from API specs"
  homepage "https://github.com/lathe-cli/lathe"
  version "0.3.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v0.3.0/lathe_0.3.0_darwin_arm64.tar.gz"
      sha256 "a7e97095da37e60deb2f0e36a52efdc8a4b85d44094036b57914bb0009796135"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v0.3.0/lathe_0.3.0_darwin_amd64.tar.gz"
      sha256 "a8698648cafc1bc5678ce8797de8e2d03e4f28a53edc87d6f3b1ceb0851840a0"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v0.3.0/lathe_0.3.0_linux_arm64.tar.gz"
      sha256 "aae32e6d64f842ad22a0b2a11590e821a614d67037fb229afeefb7d7bc75ce33"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v0.3.0/lathe_0.3.0_linux_amd64.tar.gz"
      sha256 "e5cfe19ba3fb59f16b4f888b6ff3a708e8993796079a33fc66204a44404538c4"
    end
  end

  def install
    bin.install "lathe"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lathe version")
  end
end
