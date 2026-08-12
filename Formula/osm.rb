class Osm < Formula
  desc "Send encrypted messages through any chat using published SSH keys"
  homepage "https://github.com/gufranco/osm"
  url "https://github.com/gufranco/osm/archive/refs/tags/v1.5.0.tar.gz"
  sha256 "24e36da1019888a8789dbb93047f32aa6acb0c5709dcd87dc83748dccdb26ac0"
  license "MIT"
  head "https://github.com/gufranco/osm.git", branch: "main"

  depends_on "age"

  def install
    system "bash", "build.sh"
    bin.install "dist/osm"
    man1.install "man/osm.1"
    bash_completion.install "completions/osm.bash" => "osm"
    zsh_completion.install "completions/_osm"
    fish_completion.install "completions/osm.fish"
  end

  test do
    assert_match "osm #{version}", shell_output("#{bin}/osm version")
    assert_match "osm send", shell_output("#{bin}/osm help")
    system bin/"osm", "doctor"
  end
end
