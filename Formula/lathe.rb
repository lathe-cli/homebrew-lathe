class Lathe < Formula
  desc "Generate agent-friendly Cobra CLIs from API specs"
  homepage "https://github.com/lathe-cli/lathe"
  version "0.2.4"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v0.2.4/lathe_0.2.4_darwin_arm64.tar.gz"
      sha256 "b1b2e2958376b12f26c3061e6b5693299edb4317f795b68f10bdf1f8d7c2ff1a"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v0.2.4/lathe_0.2.4_darwin_amd64.tar.gz"
      sha256 "a3feba85103dd3a3a1f484e4d881e4425345cc6502cd73f4d17588a2cf93aaec"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v0.2.4/lathe_0.2.4_linux_arm64.tar.gz"
      sha256 "bd2946b79f217729f9a067a150a7fe40b91b4a46242aae8e1aa967e6eafae69d"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v0.2.4/lathe_0.2.4_linux_amd64.tar.gz"
      sha256 "a3ba46474292047d113be12a47cdbf5b7ed36c6705cf756f9f0d97633c571de1"
    end
  end

  def install
    bin.install "lathe"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lathe version")
  end
end
