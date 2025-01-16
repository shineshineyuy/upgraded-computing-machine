set -exou

export NINJAFLAGS=-j3

pushd qtwebengine-chromium

  if [[ $(uname) == "Darwin" ]]; then
    # Ensure that Chromium is built using the correct sysroot in Mac
    awk 'NR==77{$0="    \"'$CONDA_BUILD_SYSROOT'\","}1' chromium/build/config/mac/BUILD.gn > chromium/build/config/mac/BUILD.gn.tmp
    rm chromium/build/config/mac/BUILD.gn
    mv chromium/build/config/mac/BUILD.gn.tmp chromium/build/config/mac/BUILD.gn

    # awk 'NR==95{$0="  ldflags += [ \"-L/Users/builder/jcmorin/miniconda/envs/qt-webengine/lib\", \"-nostdlib++\", \"-Wl,-rpath,/Users/builder/jcmorin/miniconda/envs/qt-webengine/lib\", \"-lc++\" ]"}1' chromium/build/config/mac/BUILD.gn > chromium/build/config/mac/BUILD.gn.tmp
    # rm chromium/build/config/mac/BUILD.gn
    # mv chromium/build/config/mac/BUILD.gn.tmp chromium/build/config/mac/BUILD.gn

    # awk 'NR==79{$0="    \"-isystem\",\n    \"/Users/builder/jcmorin/miniconda/envs/qt-webengine/include/c++/v1\",\n    \"-nostdinc++\",\n  ]"}1' chromium/build/config/mac/BUILD.gn > chromium/build/config/mac/BUILD.gn.tmp
    # rm chromium/build/config/mac/BUILD.gn
    # mv chromium/build/config/mac/BUILD.gn.tmp chromium/build/config/mac/BUILD.gn
  fi
  # we don't want to play with git ... too slow ...
popd

pushd qtwebengine
pushd src/3rdparty
  # copy the patched 3rdparty stuff ... and make sure we don't play with git
  rm -rf *
  cp -R ../../../qtwebengine-chromium/* .
popd

if [[ $target_platform == osx-* ]]; then
    # Make sure config.guess is up to date, if required
    list_config_to_patch=$(find . -name config.guess | sed -E 's/config.guess//')
    for config_folder in $list_config_to_patch; do
        echo "copying config to $config_folder ...\n"
        cp -v $BUILD_PREFIX/share/libtool/build-aux/config.* $config_folder
    done
    # create a matching 'strip' tool in prefix/bin
    mkdir -p $PREFIX/bin
    where=$(which "llvm-strip" 2>/dev/null || true)
    if [ -n "${where}" ]; then
        printf "#!/bin/bash\nexec '${where}' \"\${@}\"\n" >"${PREFIX}/bin/strip"
        chmod 700 "${PREFIX}/bin/strip"
    fi
    if [ ! -f "${BUILD_PREFIX}/bin/clang++" ]; then
    if [ -n "${CXX}" ]; then
        printf "#!/bin/bash\nexec '${CXX}' \"\${@}\"\n" >"${BUILD_PREFIX}/bin/clang++"
        chmod 700 "${BUILD_PREFIX}/bin/clang++"
    fi
    fi
    if [ ! -f "${BUILD_PREFIX}/bin/clang" ]; then
    if [ -n "${CC}" ]; then
        printf "#!/bin/bash\nexec '${CC}' \"\${@}\"\n" >"${BUILD_PREFIX}/bin/clang"
        chmod 700 "${BUILD_PREFIX}/bin/clang"
    fi
    fi
    export CONFIG_SHELL="/bin/bash"
    export SHELL="/bin/bash" 
fi

# required to populate include ...
if [ ! -f "./include/QtWebEngineCore/qtwebenginecoreglobal.h" ]; then
  echo "Creating headers ..."
  ${PREFIX}/bin/syncqt.pl -version 5.15.9
  echo "Testing existance of headers ..."
  # abort if this doesn't get created by syncqt.pl
  test -f "./include/QtWebEngineCore/qtwebenginecoreglobal.h"
fi

mkdir qtwebengine-build
pushd qtwebengine-build

USED_BUILD_PREFIX=${BUILD_PREFIX:-${PREFIX}}
echo USED_BUILD_PREFIX=${BUILD_PREFIX}

# qtwebengine needs python 2, osx we can use system one ...
# (lucky we are, as there is no python 2.7 for osx-arm64)
if [[ $target_platform == osx-arm64 ]]; then
  echo "Using system python2 ... "
elif [[ $target_platform == linux-aarch64 ]]; then
  echo "Attempt to use system python2 ..."
else
  conda create --yes -p "${SRC_DIR}/python2_hack" --quiet python=2
  export PATH=${SRC_DIR}/python2_hack/bin:${PATH}
fi

if [[ $(uname) == "Linux" ]]; then
    ln -s ${GXX} g++ || true
    ln -s ${GCC} gcc || true
    ln -s ${USED_BUILD_PREFIX}/bin/${HOST}-gcc-ar gcc-ar || true

    export LD=${GXX}
    export CC=${GCC}
    export CXX=${GXX}

    chmod +x g++ gcc gcc-ar
    export PATH=$PREFIX/bin:${PWD}:${PATH}

    which pkg-config
    export PKG_CONFIG_EXECUTABLE=$(which pkg-config)
    # Currently uses system's libxkbfile library (which needs to be available locally), hence /usr/lib64/pkgconfig 
    # is added to PKG_CONFIG_PATH to locate it.
    export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig/:$BUILD_PREFIX/lib/pkgconfig/:/usr/lib64/pkgconfig

    # Set QMake prefix to $PREFIX
    qmake -set prefix $PREFIX

    qmake QMAKE_LIBDIR=${PREFIX}/lib \
        QMAKE_LFLAGS+="-Wl,-rpath,$PREFIX/lib -Wl,-rpath-link,$PREFIX/lib -L$PREFIX/lib" \
        INCLUDEPATH+="${PREFIX}/include" \
        PKG_CONFIG_EXECUTABLE=$(which pkg-config) \
        ..

    #cat config.log
    #exit 1
    CPATH=$PREFIX/include:$BUILD_PREFIX/src/core/api make -j$CPU_COUNT
    make install
fi

if [[ $(uname) == "Darwin" ]]; then
    # Let Qt set its own flags and vars
    for x in OSX_ARCH CFLAGS CXXFLAGS LDFLAGS
    do
        unset $x
    done

    # Qt passes clang flags to LD (e.g. -stdlib=c++)
    export LD=${CXX}
    export AS=${CXX}
    export OBJC=${CC}
    export OBJCXX=${CXX}

    export SED=${BUILD_PREFIX}/bin/sed
    export PATH=${PWD}:${PATH}

    # Use xcode-avoidance scripts
    export PATH=$PREFIX/bin/xc-avoidance:$PATH

    export APPLICATION_EXTENSION_API_ONLY=NO

    EXTRA_FLAGS=""
    if [[ $(arch) == "arm64" ]]; then
      EXTRA_FLAGS="QMAKE_APPLE_DEVICE_ARCHS=arm64"
    fi

    # Set QMake prefix to $PREFIX
    qmake -set prefix $PREFIX

    # sed -i '' -e 's/-Werror//' $PREFIX/mkspecs/features/qt_module_headers.prf

    # TODO: Figure out why this isn't printing a summary on osx...
    # While being there, we should also figure out why "set -x" doens't seem to be applied...
    qmake QMAKE_LIBDIR=${PREFIX}/lib \
        INCLUDEPATH+="${PREFIX}/include" \
        CONFIG+="warn_off" \
        QMAKE_CFLAGS_WARN_ON="-w" \
        QMAKE_CXXFLAGS_WARN_ON="-w" \
        QMAKE_CFLAGS+="-Wno-everything" \
        QMAKE_CXXFLAGS+="-Wno-everything" \
        $EXTRA_FLAGS \
        QMAKE_LFLAGS+="-w -Wno-everything -Wl,-rpath,$PREFIX/lib -L$PREFIX/lib" \
        PKG_CONFIG_EXECUTABLE=$(which pkg-config) \
        ..

    # -Xlinker -no_application_extension
    # find . -type f -exec sed -i '' -e 's/-Wl,-fatal_warnings//g' {} +
    # sed -i '' -e 's/-Werror//' $PREFIX/mkspecs/features/qt_module_headers.prf

    make -j$CPU_COUNT
    make install
fi

# Post build setup
# ----------------

# Remove temporary files in $PREFIX/bin
rm -f "${PREFIX}/bin/strip"

# Remove static libraries that are not part of the Qt SDK.
pushd "${PREFIX}"/lib > /dev/null
    find . -name "*.a" -and -not -name "libQt*" -exec rm -f {} \;
popd > /dev/null
