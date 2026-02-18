class Vault < Formula
  desc "Lock down sensitive files before screen sharing or interviews"
  homepage "https://github.com/gabrielkoerich/vault"
  url "https://github.com/gabrielkoerich/vault/archive/refs/tags/v0.1.0.tar.gz"
  sha256 ""
  head "https://github.com/gabrielkoerich/vault.git", branch: "main"
  license "MIT"

  depends_on "age"

  def install
    bin.install "vault"
  end

  def caveats
    <<~EOS
      Create your config at ~/.config/vault/paths with one sensitive path per line:

        $HOME/.private
        $HOME/.ssh
        $HOME/.config/solana

      Then run `vault scan` to auto-detect more, or `vault lockdown` before a call.
    EOS
  end

  test do
    assert_match "vault", shell_output("#{bin}/vault version")
  end
end
