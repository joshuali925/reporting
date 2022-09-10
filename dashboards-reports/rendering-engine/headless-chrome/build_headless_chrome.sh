#!/bin/bash

set -e

# Initializes a Linux environment. This need only be done once per
# machine. The OS needs to be a flavor that supports apt get, such as Ubuntu.

function generateArgs {
if [ $1 == 'linux' ];  then
  echo 'import("//build/args/headless.gn")
is_component_build = false
remove_webcore_debug_symbols = true
enable_nacl = false
is_debug = false
symbol_level = 0
use_kerberos = false' > args.gn
elif [ $1 == 'darwin' ]; then
  echo '#args configuration

icu_use_data_file = false
v8_use_external_startup_data = false
remove_webcore_debug_symbols = true
use_kerberos = false
use_libpci = false
use_pulseaudio = false
use_udev = false
is_debug = false
symbol_level = 0
is_component_build = false
enable_nacl = false
enable_print_preview = false
enable_basic_printing = false
enable_remoting = false
use_alsa = false
use_cups = false
use_dbus = false
use_gio = false
' > args.gn
fi
}

if [ "$#" -lt 1 ];
then
   echo "format: build_headless_chrome.sh {chrome_source_version} (arch_name)"
   echo "Mac x64: ./build_headless_chrome.sh  312d84c8ce62810976feda0d3457108a6dfff9e6"
   echo "Mac arm64: ./build_headless_chrome.sh  312d84c8ce62810976feda0d3457108a6dfff9e6 arm64"
   echo "Linux x64: ./build_headless_chrome.sh 312d84c8ce62810976feda0d3457108a6dfff9e6"
   echo "Linux arm64: ./build_headless_chrome.sh 312d84c8ce62810976feda0d3457108a6dfff9e6 arm64"
   exit
fi

source_version=$1

if [ "$#" -lt 2 ];
then
   arch_name="x64"
else
  arch_name=$2
fi

if ! [ -x "$(command -v python)" ]; then
  echo "Python is not found, please install python or setup python environment properly"
  exit
fi

if [ "$#" -eq 2 ]; then
  arch_name=$2
fi

current_folder=$(pwd)

# find the current platform
platform_name='unknown'
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  platform_name='linux'
elif [[ "$OSTYPE" == "darwin"* ]]; then
  platform_name='darwin'
elif [[ "$OSTYPE" == "win32" ]]; then
  platform_name='windows'
fi

if [[ "$platform_name" == "unknown" ]]; then
  echo "platform is"  $platform_name
  exit
fi

echo "source_version = " $source_version
echo "platform_name = " $platform_name
echo "arch_name = " $arch_name
generateArgs $platform_name

# Configure git
git config core.autocrlf false
git config core.filemode false
git config branch.autosetuprebase always

# Grab Chromium's custom build tools, if they aren't already installed
# (On Windows, they are installed before this Python script is run)
if ! [ -d "depot_tools" ]
then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git --depth=1
fi

# Put depot_tools on the path so we can properly run the fetch command
export PATH="$PWD/depot_tools:$PATH"
ls ${PWD}/depot_tools

# Fetch the Chromium source code

if [ -d 'chromium' ]; then
  echo "chromium src aready exists, please delete it and retry..."
  exit
fi

mkdir -p chromium
cd chromium
pwd

# Build Linux deps
echo "fetching chromium..."
fetch chromium


# Build Linux deps

cd src

if [[ "$platform_name" = "linux" ]]; then
  if [[ "$arch_name" = "arm64" ]]; then
    ./build/linux/sysroot_scripts/install-sysroot.py --arch=$arch_name
  fi
  if builtin command -v yum > /dev/null 2>&1; then
    sudo yum install git python bzip2 tar pkgconfig atk-devel alsa-lib-devel \
      bison binutils brlapi-devel bluez-libs-devel bzip2-devel cairo-devel \
      cups-devel dbus-devel dbus-glib-devel expat-devel fontconfig-devel \
      freetype-devel gcc-c++ glib2-devel glibc.i686 gperf glib2-devel \
      gtk3-devel java-1.*.0-openjdk-devel libatomic libcap-devel libffi-devel \
      libgcc.i686 libgnome-keyring-devel libjpeg-devel libstdc++.i686 libX11-devel \
      libXScrnSaver-devel libXtst-devel libxkbcommon-x11-devel ncurses-compat-libs \
      nspr-devel nss-devel pam-devel pango-devel pciutils-devel \
      pulseaudio-libs-devel zlib.i686 httpd mod_ssl php php-cli python-psutil wdiff \
      xorg-x11-server-Xvfb
  else
    ./build/install-build-deps.sh
  fi
fi


# Set to "arm" to build for ARM on Linux
echo 'Building Chromium '  $source_version  ' for '  $arch_name

# Sync the codebase to the correct version, syncing master first
# to ensure that we actually have all the versions we may refer to
echo 'Syncing source code'


git checkout -f main
git fetch -f origin
gclient sync --with_branch_heads --with_tags --jobs 16
git checkout $source_version
gclient sync --with_branch_heads --with_tags --jobs 16
gclient runhooks
echo "current_folder :" $current_folder

platform_build_args=$current_folder'/args.gn'
#platform_build_args=$current_folder/chromium/build_chromium/$platform_name/args.gn

mkdir -p 'out/headless'

echo "platform_build_args :" $platform_build_args

cp $platform_build_args 'out/headless/args.gn'
echo 'target_cpu = '\"$arch_name\"  >> 'out/headless/args.gn'

gn gen out/headless

autoninja -C out/headless headless_shell

if [[ ($platform_name != "Windows" && $arch_name != 'arm64')  ]]; then
  echo 'Optimizing headless_shell'
  mv out/headless/headless_shell out/headless/headless_shell_raw
  strip -o out/headless/headless_shell out/headless/headless_shell_raw
fi
