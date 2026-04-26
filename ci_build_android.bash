#!/bin/bash
set -e

export LWJGL_LIBDIR=$(dirname $(realpath $(find -type f -name "liblwjgl.so")))

echo $LWJGL_LIBDIR

export NDK_VERSION=r28c

wget https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux.zip
unzip android-ndk-$NDK_VERSION-linux.zip > /dev/null
export ANDROID_NDK_HOME=$PWD/android-ndk-$NDK_VERSION

export LIBFFI_VERSION=3.4.6
export ANDROID=1 LWJGL_BUILD_OFFLINE=1
#export LWJGL_BUILD_ARCH=arm64

# Setup env
if   [ "$LWJGL_BUILD_ARCH" == "arm64" ]; then
  export NDK_ABI=arm64-v8a NDK_TARGET=aarch64
elif [ "$LWJGL_BUILD_ARCH" == "arm32" ]; then
  export NDK_ABI=armeabi-v7a NDK_TARGET=armv7a NDK_SUFFIX=eabi
elif [ "$LWJGL_BUILD_ARCH" == "x86" ]; then
  export NDK_ABI=x86 NDK_TARGET=i686
  # Workaround: LWJGL 3 lacks of x86 Linux libraries
  mkdir -p bin/libs/native/linux/x86/org/lwjgl/{freetype,glfw,openal}
  touch bin/libs/native/linux/x86/org/lwjgl/{freetype/libfreetype.so,glfw/libglfw.so,openal/libopenal.so}
elif [ "$LWJGL_BUILD_ARCH" == "x64" ]; then
  export NDK_ABI=x86_64 NDK_TARGET=x86_64
fi

export TARGET=$NDK_TARGET-linux-android$NDK_SUFFIX
export PATH=$PATH:$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin

LWJGL_NATIVE=bin/libs/native/linux/$LWJGL_BUILD_ARCH/org/lwjgl
mkdir -p $LWJGL_NATIVE

if [ "$SKIP_LIBFFI" != "1" ]; then
  # Get libffi
  if [ ! -d libffi ]; then
    wget https://github.com/libffi/libffi/releases/download/v$LIBFFI_VERSION/libffi-$LIBFFI_VERSION.tar.gz
    tar xvf libffi-$LIBFFI_VERSION.tar.gz > /dev/null
    mv libffi-$LIBFFI_VERSION libffi
  fi
  cd libffi

  # Build libffi
  bash configure --host=$TARGET --prefix=$PWD/$NDK_TARGET-unknown-linux-android$NDK_SUFFIX CC=${TARGET}21-clang CXX=${TARGET}21-clang++
  make -j4
  cd ..

  # Copy libffi
  cp libffi/$NDK_TARGET-linux-android$NDK_SUFFIX/.libs/libffi.a $LWJGL_NATIVE/
fi

# HACK: Skip compiling and running the generator to save time and keep LWJGLX functions
mkdir -p bin/classes/{generator,templates/META-INF}
touch bin/classes/{generator,templates}/touch.txt bin/classes/generator/generated-touch.txt

# Build LWJGL 3
ant -version

export ANTFLAGS= -Dplatform.linux=true \
  -Dbinding.assimp=false \
  -Dbinding.bgfx=false \
  -Dbinding.cuda=false \
  -Dbinding.egl=false \
  -Dbinding.fmod=false \
  -Dbinding.harfbuzz=false \
  -Dbinding.hwloc=false \
  -Dbinding.jawt=false \
  -Dbinding.jemalloc=false \
  -Dbinding.ktx=false \
  -Dbinding.libdivide=false \
  -Dbinding.llvm=false \
  -Dbinding.lmdb=false \
  -Dbinding.lz4=false \
  -Dbinding.meow=false \
  -Dbinding.meshoptimizer=false \
  -Dbinding.nfd=false \
  -Dbinding.nuklear=false \
  -Dbinding.odbc=false \
  -Dbinding.opencl=false \
  -Dbinding.openvr=false \
  -Dbinding.openxr=false \
  -Dbinding.opus=false \
  -Dbinding.par=false \
  -Dbinding.remotery=false \
  -Dbinding.rpmalloc=false \
  -Dbinding.spvc=false \
  -Dbinding.sse=false \
  -Dbinding.tinyexr=false \
  -Dbinding.tootle=false \
  -Dbinding.xxhash=false \
  -Dbinding.yoga=false \
  -Dbinding.zstd=false \
  -Dbinding.stb=false \
  -Dbinding.tinyfd=false \
  -Dbinding.vma=false \
  -Dbinding.vulkan=false \
  -Dbinding.shaderc=false \
  -Dbinding.freetype=false \
  -Dbinding.msdfgen=false \
  -Dbinding.nanovg=false \
  -Dbuild.type=release/3.3.3 \
  -Djavadoc.skip=true \

yes | ant $ANTFLAGS \
  -Dnashorn.args="--no-deprecation-warning" \
  compile compile-native

yes | ant $ANTFLAGS \
  -Dbuild.offline=true \
  release


# Copy native libraries
rm -rf bin/out; mkdir bin/out
find bin/RELEASE -name '*-natives-*' -exec cp {} bin/out/ \;

# Cleanup unused output jar files
find bin/RELEASE \( -name '*-natives-*' -o -name '*-sources.jar' \) -delete

#Run through retrolambda
wget https://repo1.maven.org/maven2/net/orfjackal/retrolambda/retrolambda/2.5.7/retrolambda-2.5.7.jar

mkdir "retrolambda-in"
pushd "retrolambda-in"
find ../bin/RELEASE -type f -name "*.jar" -not -name "*-natives*" | xargs -n 1 unzip -o
rm -rf META-INF
popd

mkdir retrolambda-out

$JAVA8_HOME/bin/java -Djava.library.path=$LWJGL_LIBDIR -Dretrolambda.bytecodeVersion=50 -Dretrolambda.defaultMethods=true -Dretrolambda.inputDir=retrolambda-in -Dretrolambda.outputDir=retrolambda-out -Dretrolambda.classpath=retrolambda-in -jar retrolambda-2.5.7.jar

pushd retrolambda-out
zip -r lwjgl-rl.jar .
popd

cp retrolambda-out/lwjgl-rl.jar bin/RELEASE/
