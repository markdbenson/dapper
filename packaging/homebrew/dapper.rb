# Homebrew formula for dapper. It installs the single-file build attached to
# each GitHub release. The release workflow copies it, with the new version
# and checksum, to Formula/dapper.rb in the markdbenson/homebrew-tap
# repository (see RELEASING.md). Then:
#
#   brew install markdbenson/tap/dapper

class Dapper < Formula
  desc "Static site generator: Markdown in, plain HTML out"
  homepage "https://github.com/markdbenson/dapper"
  url "https://github.com/markdbenson/dapper/releases/download/v1.10/dapper"
  version "1.10"
  sha256 "de9309aa9ff9a8b50fa0c23d7cd73e8d438858beba5d6324f328add631c373a6"
  license "MIT"

  uses_from_macos "perl"

  def install
    bin.install "dapper"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/dapper -v")
    system bin/"dapper", "-q", "init", "--template", "blog"
    system bin/"dapper", "-q", "build"
    assert_path_exists testpath/"_output/index.html"
  end
end
