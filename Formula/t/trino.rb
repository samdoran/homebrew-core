class Trino < Formula
  include Language::Python::Shebang

  desc "Distributed SQL query engine for big data"
  homepage "https://trino.io"
  url "https://search.maven.org/remotecontent?filepath=io/trino/trino-server/428/trino-server-428.tar.gz", using: :nounzip
  sha256 "4b880617f35592eb1f635e6e48d8e4d1622527a748021c7039d287b8d98f4e3a"
  license "Apache-2.0"

  livecheck do
    url "https://search.maven.org/remotecontent?filepath=io/trino/trino-server/"
    regex(%r{href=["']?v?(\d+(?:\.\d+)*)/?["' >]}i)
  end

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_ventura:  "f6ebb41d27a16d3fe44ae2517c134ddccf7b596d81019eb81e5bf4568caa343a"
    sha256 cellar: :any_skip_relocation, arm64_monterey: "f6ebb41d27a16d3fe44ae2517c134ddccf7b596d81019eb81e5bf4568caa343a"
    sha256 cellar: :any_skip_relocation, arm64_big_sur:  "f6ebb41d27a16d3fe44ae2517c134ddccf7b596d81019eb81e5bf4568caa343a"
    sha256 cellar: :any_skip_relocation, ventura:        "f6ebb41d27a16d3fe44ae2517c134ddccf7b596d81019eb81e5bf4568caa343a"
    sha256 cellar: :any_skip_relocation, monterey:       "f6ebb41d27a16d3fe44ae2517c134ddccf7b596d81019eb81e5bf4568caa343a"
    sha256 cellar: :any_skip_relocation, big_sur:        "f6ebb41d27a16d3fe44ae2517c134ddccf7b596d81019eb81e5bf4568caa343a"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "080e1b7d67d173370fe5823937d264b6b4731ea7d4e76ee9eb414c84016718a1"
  end

  depends_on "gnu-tar" => :build
  depends_on "openjdk"
  depends_on "python@3.11"

  resource "trino-src" do
    url "https://github.com/trinodb/trino/archive/refs/tags/428.tar.gz", using: :nounzip
    sha256 "03c999bdcb186fca267780bf904b44f0303c087ddc5421590094104f31c65903"
  end

  resource "trino-cli" do
    url "https://search.maven.org/remotecontent?filepath=io/trino/trino-cli/428/trino-cli-428-executable.jar"
    sha256 "e5a387cdb6ea9fd8c99757f9ddf667069435cbe7a8804b4886aa34b27f3cdcaa"
  end

  def install
    # Manually extract tarball to avoid losing hardlinks which increases bottle
    # size from MBs to GBs. Remove once Homebrew is able to preserve hardlinks.
    # Ref: https://github.com/Homebrew/brew/pull/13154
    libexec.mkpath
    system "tar", "-C", libexec.to_s, "--strip-components", "1", "-xzf", "trino-server-#{version}.tar.gz"

    # Manually untar, since macOS-bundled tar produces the error:
    #   trino-363/plugin/trino-hive/src/test/resources/<truncated>.snappy.orc.crc: Failed to restore metadata
    # Remove when https://github.com/trinodb/trino/issues/8877 is fixed
    resource("trino-src").stage do |r|
      ENV.prepend_path "PATH", Formula["gnu-tar"].opt_libexec/"gnubin"
      system "tar", "-xzf", "trino-#{r.version}.tar.gz"
      (libexec/"etc").install Dir["trino-#{r.version}/core/docker/default/etc/*"]
      inreplace libexec/"etc/node.properties", "docker", tap.user.downcase
      inreplace libexec/"etc/node.properties", "/data/trino", var/"trino/data"
      inreplace libexec/"etc/jvm.config", %r{^-agentpath:/usr/lib/trino/bin/libjvmkill.so$\n}, ""
    end

    rewrite_shebang detected_python_shebang, libexec/"bin/launcher.py"
    (bin/"trino-server").write_env_script libexec/"bin/launcher", Language::Java.overridable_java_home_env

    resource("trino-cli").stage do
      libexec.install "trino-cli-#{version}-executable.jar"
      bin.write_jar_script libexec/"trino-cli-#{version}-executable.jar", "trino"
    end

    # Remove incompatible pre-built binaries
    libprocname_dirs = libexec.glob("bin/procname/*")
    # Keep the Linux-x86_64 directory to make bottles identical
    libprocname_dirs.reject! { |dir| dir.basename.to_s == "Linux-x86_64" } if build.bottle?
    libprocname_dirs.reject! { |dir| dir.basename.to_s == "#{OS.kernel_name}-#{Hardware::CPU.arch}" }
    libprocname_dirs.map(&:rmtree)
  end

  def post_install
    (var/"trino/data").mkpath
  end

  service do
    run [opt_bin/"trino-server", "run"]
    working_dir opt_libexec
  end

  test do
    port = free_port
    cp libexec/"etc/config.properties", testpath/"config.properties"
    inreplace testpath/"config.properties", "8080", port.to_s
    server = fork do
      exec bin/"trino-server", "run", "--verbose",
                                      "--data-dir", testpath,
                                      "--config", testpath/"config.properties"
    end
    sleep 30

    query = "SELECT state FROM system.runtime.nodes"
    output = shell_output(bin/"trino --debug --server localhost:#{port} --execute '#{query}'")
    assert_match "\"active\"", output
  ensure
    Process.kill("TERM", server)
    begin
      Process.wait(server)
    rescue Errno::ECHILD
      quiet_system "pkill", "-9", "-P", server.to_s
    end
  end
end
