class Lathe < Formula
  desc "Generate agent-friendly Cobra CLIs from API specs"
  homepage "https://github.com/lathe-cli/lathe"
  version "0.4.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v0.4.0/lathe_0.4.0_darwin_arm64.tar.gz"
      sha256 "63a7a0b5863fa190ccb15074a8c4a6b5e012771c62eadc72927e44851167fe61"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v0.4.0/lathe_0.4.0_darwin_amd64.tar.gz"
      sha256 "803517a2eb6b7db54fdb0d0fdf77718eaa3343d2e553e1a11101a0f13a5ee9c7"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/lathe-cli/lathe/releases/download/v0.4.0/lathe_0.4.0_linux_arm64.tar.gz"
      sha256 "1da0d3ddb0ac67b75ddb46977b84762517ac32a22e298e9db7cad838d7e31133"
    else
      url "https://github.com/lathe-cli/lathe/releases/download/v0.4.0/lathe_0.4.0_linux_amd64.tar.gz"
      sha256 "5e0b98b48ca2286706ee4f2e26cdf26bd1d293d83ca75c9cc3813c775982510c"
    end
  end

  def install
    bin.install "lathe"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lathe version")
  end
end
