# Homebrew formula for dapper. It installs the single-file build attached to
# each GitHub release. To publish a new version, run
# packaging/homebrew/update-formula.sh <version> and copy the result to
# Formula/dapper.rb in the markdbenson/homebrew-tap repository. Then:
#
#   brew install markdbenson/tap/dapper

class Dapper < Formula
  desc "Static site generator: Markdown in, plain HTML out"
  homepage "https://github.com/markdbenson/dapper"
  url "https://github.com/markdbenson/dapper/releases/download/v1.0.0/dapper"
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256"
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
