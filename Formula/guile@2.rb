class GuileAT2 < Formula
  desc "GNU Ubiquitous Intelligent Language for Extensions"
  homepage "https://www.gnu.org/software/guile/"
  url "https://ftp.gnu.org/gnu/guile/guile-2.2.7.tar.xz"
  mirror "https://ftpmirror.gnu.org/guile/guile-2.2.7.tar.xz"
  sha256 "cdf776ea5f29430b1258209630555beea6d2be5481f9da4d64986b077ff37504"

  bottle do
    sha256 "35072ce02c8db7b27f6890da7244e63ecb6e37d510b8c8794be27b46b2d57cb5" => :big_sur
    sha256 "b281df6321e291747d5d847ac8c61f74f4de2777c031ca597b4f5440459f5207" => :arm64_big_sur
    sha256 "2821f055df7815abc7467a42f1bd90a09672261a9aad4ce994111a59a2ce6dbe" => :catalina
    sha256 "78e5fd69581a54b8d7c701e1fc03d96660b80a2699d7dad701cdd2865a5f2442" => :mojave
    sha256 "2832668210b0ef94ae0596c7e27aca846f76453719df6a9103e34af9e885d031" => :high_sierra
  end

  keg_only :versioned_formula

  deprecate! date: "2020-04-07", because: :versioned_formula

  depends_on "gnu-sed" => :build
  depends_on "bdw-gc"
  depends_on "gmp"
  depends_on "libffi"
  depends_on "libtool"
  depends_on "libunistring"
  depends_on "pkg-config" # guile-config is a wrapper around pkg-config.
  depends_on "readline"

  def install
    # Avoid superenv shim
    inreplace "meta/guile-config.in", "@PKG_CONFIG@", Formula["pkg-config"].opt_bin/"pkg-config"

    system "./configure", "--disable-dependency-tracking",
                          "--prefix=#{prefix}",
                          "--with-libreadline-prefix=#{Formula["readline"].opt_prefix}",
                          "--with-libgmp-prefix=#{Formula["gmp"].opt_prefix}"
    system "make", "install"

    # A really messed up workaround required on macOS --mkhl
    Pathname.glob("#{lib}/*.dylib") do |dylib|
      lib.install_symlink dylib.basename => "#{dylib.basename(".dylib")}.so"
    end

    # This is either a solid argument for guile including options for
    # --with-xyz-prefix= for libffi and bdw-gc or a solid argument for
    # Homebrew automatically removing Cellar paths from .pc files in favour
    # of opt_prefix usage everywhere.
    inreplace lib/"pkgconfig/guile-2.2.pc" do |s|
      s.gsub! Formula["bdw-gc"].prefix.realpath, Formula["bdw-gc"].opt_prefix
      s.gsub! Formula["libffi"].prefix.realpath, Formula["libffi"].opt_prefix
    end

    (share/"gdb/auto-load").install Dir["#{lib}/*-gdb.scm"]

    # Guile allows multiple versions to run in parallel.
    # Install versioned symlinks in libexec/bin.
    {
      "guile"        => "guile-2.2",
      "guild"        => "guild-2.2",
      "guile-config" => "guile-config-2.2",
      "guile-snarf"  => "guile-snarf-2.2",
      "guile-tools"  => "guile-tools-2.2",
    }.each do |unversioned_name, versioned_name|
      (libexec/"bin").install_symlink (bin/unversioned_name).realpath => versioned_name
    end
  end

  def caveats
    <<~EOS
      Guile has been installed as
        #{opt_bin}/guile

      Versioned symlinks `guile-2.2`, `guild-2.2`, `guile-config-2.2` etc. pointing to
      `guile`, `guild`, `guile-config` etc., respectively, have been installed into
        #{opt_libexec}/bin

      Guile libraries are installed here:
          Source files: #{opt_share}/guile/site/2.2
        Compiled files: #{opt_lib}/guile/2.2/ccache
            Extensions: #{opt_lib}/guile/2.2/extensions
    EOS
  end

  test do
    hello = testpath/"hello.scm"
    hello.write <<~EOS
      (display "Hello World")
      (newline)
    EOS

    ENV["GUILE_AUTO_COMPILE"] = "0"

    system bin/"guile", hello
  end
end
