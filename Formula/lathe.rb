class Lathe < Formula
  desc "Generate agent-friendly Cobra CLIs from API specs"
  homepage "https://github.com/lathe-cli/lathe"
  version "0.7.0"
  license "Apache-2.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v#{version}/lathe_#{version}_darwin_arm64.tar.gz"
      sha256 "df79393713b055dd6ca5a6d5047e7b2b82576961aedcc97182fbb0fe3d875e92"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v#{version}/lathe_#{version}_darwin_amd64.tar.gz"
      sha256 "05dddfa0a41ab05ad6eea988bcac764a0b87fc86fdc1c4f78bd891c321b59fbf"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v#{version}/lathe_#{version}_linux_arm64.tar.gz"
      sha256 "c5710826fa3a80f2955516212a633482d1e45158938873f1dad7887982c252a3"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v#{version}/lathe_#{version}_linux_amd64.tar.gz"
      sha256 "6a91a86dc201fe53b3544978ce6b069e0e0f3bcf88ad31f237226eba7ab34a28"
    end
  end

  def install
    bin.install "lathe"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lathe version")
  end
end
