{ crossenv, libudev, libxcb, libx11, libxi, dejavu-fonts }:

let
  version = "5.8.0";

  # TODO: patch qt to not use /bin/pwd, test building it in a sandbox

  platform =
    let
      os_code =
        if crossenv.os == "windows" then "win32"
        else if crossenv.os == "macos" then "macx"
        else if crossenv.os == "linux" then "devices/linux-musl"
        else crossenv.os;
      compiler_code =
        if crossenv.compiler == "gcc" then "g++"
        else crossenv.compiler;
    in "${os_code}-${compiler_code}";

  base_src = crossenv.nixpkgs.fetchurl {
    url = https://download.qt.io/official_releases/qt/5.8/5.8.0/submodules/qtbase-opensource-src-5.8.0.tar.xz;
    sha256 = "01f07yjly7y24njl2h4hyknmi7pf8yd9gky23szcfkd40ap12wf1";
  };

  base_raw = crossenv.make_derivation {
    name = "qtbase-raw-${version}";
    inherit version;
    src = base_src;
    builder = ./builder.sh;

    patches = [
      # The .pc files have incorrect library names without this (e.g. Qt5Cored)
      ./pc-debug-name.patch

      # An #include statement in Qt contained uppercase letters, but
      # mingw-w64 headers are all lowercase.
      ./header-caps.patch

      # uxtheme.h test is broken, always returns false, and results in QtWidgets
      # apps looking bad on Windows.  https://stackoverflow.com/q/44784414/28128
      ./dont-test-uxtheme.patch

      # Add a devices/linux-musl-g++ platform to Qt, copied from
      # devices/linux-arm-generic-g++.  When we upgrade to Qt 5.9, we should
      # consider using device/linux-generic-g++ instead.
      ./mkspecs.patch

      # When cross-compiling, Qt uses some heuristics about whether to trust the
      # pkg-config executable supplied by the PKG_CONFIG environment variable.
      # These heuristics are wrong for us, so disable them, making qt use
      # pkg-config-cross.
      ./pkg-config-cross.patch

      # When the DBus session bus is not available, Qt tries to dereference a
      # null pointer, so Linux applications can't start up.
      ./dbus-null-pointer.patch

      # Look for fonts in the same directory as the application by default if
      # the QT_QPA_FONTDIR environment variable is not present.  Without this
      # patch, Qt tries to look for a font directory in the nix store that does
      # not exists, and prints warnings.
      # You must ship a .ttf, .ttc, .pfa, .pfb, or .otf font file
      # with your application (e.g. https://dejavu-fonts.github.io/ ).
      # That list of extensions comes from qbasicfontdatabase.cpp.
      ./font-dir.patch
    ];

    configure_flags =
      "-opensource -confirm-license " +
      "-xplatform ${platform} " +
      "-device-option CROSS_COMPILE=${crossenv.host}- " +
      "-release " +  # change to -debug if you want debugging symbols
      "-static " +
      "-pkg-config " +
      "-nomake examples " +
      "-no-icu " +
      "-no-fontconfig " +
      "-no-reduce-relocations " +
      ( if crossenv.os == "windows" then "-opengl desktop"
        else if crossenv.os == "linux" then
          "-qpa xcb " +
          "-system-xcb " +
          "-no-opengl "
        else "" );

     cross_inputs =
       if crossenv.os == "linux" then [
           libudev  # not sure if this helps, but Qt does look for it
           libx11
           libxcb
           libxcb.util
           libxcb.util-image
           libxcb.util-wm
           libxcb.util-keysyms
           libxcb.util-renderutil
           libxi
         ]
       else [];
  };

  # This wrapper aims to make Qt easier to use by generating CMake package files
  # for it.  The existing support for CMake in Qt does not handle static
  # linking; other projects maintian large, messy patches to fix it, but we
  # prefer to generate the CMake files in a clean way from scratch.
  base = crossenv.make_derivation {
    name = "qtbase-${version}";
    inherit version;
    os = crossenv.os;
    qtbase = base_raw;
    cross_inputs = base_raw.cross_inputs;
    builder.ruby = ./wrapper_builder.rb;
  };

  examples = crossenv.make_derivation {
    name = "qtbase-examples-${version}";
    inherit version;
    os = crossenv.os;
    qtbase = base;
    cross_inputs = [ base ];
    dejavu = dejavu-fonts;
    builder = ./examples_builder.sh;
  };

  license_fragment = crossenv.native.make_derivation {
    name = "qtbase-${version}-license-fragment";
    inherit version;
    src = base_src;
    builder = ./license_builder.sh;
  };
in
base // {
  recurseForDerivations = true;
  inherit base_src;
  inherit base_raw;
  inherit base;
  inherit examples;
  inherit license_fragment;
}
