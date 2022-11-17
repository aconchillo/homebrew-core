class Guile < Formula
  desc "GNU Ubiquitous Intelligent Language for Extensions"
  homepage "https://www.gnu.org/software/guile/"
  url "https://ftp.gnu.org/gnu/guile/guile-3.0.8.tar.xz"
  mirror "https://ftpmirror.gnu.org/guile/guile-3.0.8.tar.xz"
  sha256 "daa7060a56f2804e9b74c8d7e7fe8beed12b43aab2789a38585183fcc17b8a13"
  license "LGPL-3.0-or-later"
  revision 3

  bottle do
    sha256 arm64_ventura:  "c3d30012c9169556511cdf762f9c4c98dd7eca3c0ba510dac1a8ef1c14e9927a"
    sha256 arm64_monterey: "56fc54551418481510668be3665501ebae56e681856c761d2246117760e18b7a"
    sha256 arm64_big_sur:  "e60bb58c6fdfca0d7c5f948cb75dbd2767ba12588d9e60abd55f7cc6d1b089f5"
    sha256 ventura:        "2d717f010f0107b92602c54c536fd6965ea6558091ab9ba1074d28828e7326cc"
    sha256 monterey:       "73a962893b19f8b57f53183b6366029a65c292fa2dc8fa73ee15d13a897faf7b"
    sha256 big_sur:        "f7b6347634567f73383b9c1d2c1a04168f8a10d352bc386b633b60cf47abaa76"
    sha256 catalina:       "d797092caee30cc7da0e8c22c2f7416db7f317090832529926acae0a408e1ce7"
    sha256 x86_64_linux:   "cac793bc25c769435753ac8a5ca98efe420612f8946b8fa193dc69dd45e12b58"
  end

  head do
    url "https://git.savannah.gnu.org/git/guile.git", branch: "main"

    depends_on "autoconf" => :build
    depends_on "automake" => :build
    depends_on "gettext" => :build
    uses_from_macos "flex" => :build
  end

  ### Remove after configure.ac patch is not necessary anymore.
  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "gettext" => :build
  ###

  depends_on "gnu-sed" => :build
  depends_on "bdw-gc"
  depends_on "gmp"
  depends_on "libtool"
  depends_on "libunistring"
  depends_on "pkg-config" # guile-config is a wrapper around pkg-config.
  depends_on "readline"

  ### Remove after configure.ac patch is not necessary anymore.
  uses_from_macos "flex" => :build
  ###

  uses_from_macos "gperf"
  uses_from_macos "libffi", since: :catalina
  uses_from_macos "libxcrypt"

  on_macos do
    # A patch to fix JIT on Apple Silicon is embedded below, this fixes:
    #   https://debbugs.gnu.org/cgi/bugreport.cgi?bug=44505
    # The patch has not been yet reviewed/accepted upstream, but when it
    # does we should remove it from here.
    #   https://lists.gnu.org/archive/html/guile-devel/2022-11/msg00017.html
    patch :DATA
  end

  def install
    # Avoid superenv shim
    inreplace "meta/guile-config.in", "@PKG_CONFIG@", Formula["pkg-config"].opt_bin/"pkg-config"

    if OS.mac?
      # We need to regenerate ./configure because we just patched configure.ac.
      system "autoreconf", "-vif"
    else
      system "./autogen.sh" unless build.stable?
    end

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
    inreplace lib/"pkgconfig/guile-3.0.pc" do |s|
      s.gsub! Formula["bdw-gc"].prefix.realpath, Formula["bdw-gc"].opt_prefix
      s.gsub! Formula["libffi"].prefix.realpath, Formula["libffi"].opt_prefix if MacOS.version < :catalina
    end

    (share/"gdb/auto-load").install Dir["#{lib}/*-gdb.scm"]
  end

  def post_install
    # Create directories so installed modules can create links inside.
    (HOMEBREW_PREFIX/"lib/guile/3.0/site-ccache").mkpath
    (HOMEBREW_PREFIX/"lib/guile/3.0/extensions").mkpath
    (HOMEBREW_PREFIX/"share/guile/site/3.0").mkpath
  end

  def caveats
    <<~EOS
      Guile libraries can now be installed here:
          Source files: #{HOMEBREW_PREFIX}/share/guile/site/3.0
        Compiled files: #{HOMEBREW_PREFIX}/lib/guile/3.0/site-ccache
            Extensions: #{HOMEBREW_PREFIX}/lib/guile/3.0/extensions

      Add the following to your .bashrc or equivalent:
        export GUILE_LOAD_PATH="#{HOMEBREW_PREFIX}/share/guile/site/3.0"
        export GUILE_LOAD_COMPILED_PATH="#{HOMEBREW_PREFIX}/lib/guile/3.0/site-ccache"
        export GUILE_SYSTEM_EXTENSIONS_PATH="#{HOMEBREW_PREFIX}/lib/guile/3.0/extensions"
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

__END__
diff --git a/configure.ac b/configure.ac
index b3879df1f..f8c12f0d7 100644
--- a/configure.ac
+++ b/configure.ac
@@ -1187,6 +1187,9 @@ case "$with_threads" in
       pthread_get_stackaddr_np pthread_attr_get_np pthread_sigmask	\
       pthread_cancel])
 
+    # Apple Silicon JIT code arena needs to be unprotected before writing.
+    AC_CHECK_FUNCS([pthread_jit_write_protect_np])
+
     # On past versions of Solaris, believe 8 through 10 at least, you
     # had to write "pthread_once_t foo = { PTHREAD_ONCE_INIT };".
     # This is contrary to POSIX:
diff --git a/libguile/jit.c b/libguile/jit.c
index 8420829b4..5cef8fae3 100644
--- a/libguile/jit.c
+++ b/libguile/jit.c
@@ -47,6 +47,10 @@
 #include <sys/mman.h>
 #endif
 
+#if defined __APPLE__ && HAVE_PTHREAD_JIT_WRITE_PROTECT_NP
+#include <libkern/OSCacheControl.h>
+#endif
+
 #include "jit.h"
 
 
@@ -1349,9 +1353,13 @@ allocate_code_arena (size_t size, struct code_arena *prev)
   ret->size = size;
   ret->prev = prev;
 #ifndef __MINGW32__
+  int flags = MAP_PRIVATE | MAP_ANONYMOUS;
+#if defined __APPLE__ && HAVE_PTHREAD_JIT_WRITE_PROTECT_NP
+  flags |= MAP_JIT;
+#endif
   ret->base = mmap (NULL, ret->size,
                     PROT_EXEC | PROT_READ | PROT_WRITE,
-                    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
+                    flags, -1, 0);
   if (ret->base == MAP_FAILED)
     {
       perror ("allocating JIT code buffer failed");
@@ -1406,11 +1414,21 @@ emit_code (scm_jit_state *j, void (*emit) (scm_jit_state *))
 
       uint8_t *ret = jit_address (j->jit);
 
+#if defined __APPLE__ && HAVE_PTHREAD_JIT_WRITE_PROTECT_NP
+      pthread_jit_write_protect_np(0);
+#endif
+
       emit (j);
 
       size_t size;
       if (!jit_has_overflow (j->jit) && jit_end (j->jit, &size))
         {
+#if defined __APPLE__ && HAVE_PTHREAD_JIT_WRITE_PROTECT_NP
+          /* protect previous code arena. leave unprotected after emit()
+             since jit_end() also writes to code arena. */
+          pthread_jit_write_protect_np(1);
+          sys_icache_invalidate(arena->base, arena->size);
+#endif
           ASSERT (size <= (arena->size - arena->used));
           DEBUG ("mcode: %p,+%zu\n", ret, size);
           arena->used += size;
@@ -1424,6 +1442,11 @@ emit_code (scm_jit_state *j, void (*emit) (scm_jit_state *))
         }
       else
         {
+#if defined __APPLE__ && HAVE_PTHREAD_JIT_WRITE_PROTECT_NP
+          /* protect previous code arena */
+          pthread_jit_write_protect_np(1);
+          sys_icache_invalidate(arena->base, arena->size);
+#endif
           jit_reset (j->jit);
           if (arena->used == 0)
             {
