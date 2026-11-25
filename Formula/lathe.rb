class Lathe < Formula
  desc "Generate agent-friendly Cobra CLIs from API specs"
  homepage "https://github.com/lathe-cli/lathe"
  version "0.6.5"
  license "Apache-2.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v#{version}/lathe_#{version}_darwin_arm64.tar.gz"
      sha256 "acfd96aeb582040e567b97b5c98701785bb71c441bd68f70bda4e829c8a5f29f"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v#{version}/lathe_#{version}_darwin_amd64.tar.gz"
      sha256 "fed7443b8a92a4a7eca23a6b3b107c5fb485e683e831d90d5615c4550c1c38da"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v#{version}/lathe_#{version}_linux_arm64.tar.gz"
      sha256 "2c7ab96c523343c972fddc26a60f9ecb6b65fa62e2d2f1ae81c2c5ee9c431a8d"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v#{version}/lathe_#{version}_linux_amd64.tar.gz"
      sha256 "be71f2d8ea6eb05a3359a26757415a5b43c6c40c40434047a21b15cb89ca0487"
    end
  end

  def install
    bin.install "lathe"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lathe version")
  end
end
