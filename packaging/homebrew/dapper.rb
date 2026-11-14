# Homebrew formula for dapper. It installs the single-file build attached to
# each GitHub release. The release workflow copies it, with the new version
# and checksum, to Formula/dapper.rb in the markdbenson/homebrew-tap
# repository (see RELEASING.md). Then:
#
#   brew install markdbenson/tap/dapper

class Dapper < Formula
  desc "Static site generator: Markdown in, plain HTML out"
  homepage "https://github.com/markdbenson/dapper"
  url "https://github.com/markdbenson/dapper/releases/download/v1.00/dapper"
  version "1.00"
  sha256 "2a581015ee341e3580159edefa01ba0bc2033e0e3338e780adbb55c303ca5543"
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
