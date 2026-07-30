# Building GOALPad

## Requirements

- Apple silicon Mac
- Xcode 26.6 or a compatible toolchain with the iOS 26.5 SDK
- CMake, Ninja, and OpenSSL 3 for the OpenGOAL host baseline

```sh
brew install cmake ninja go-task openssl@3
```

## Initialize OpenGOAL

```sh
git submodule update --init --recursive
```

The submodule commit is the authoritative upstream version. Do not substitute a
different OpenGOAL checkout when recording validation results.

## Build the application

From the repository root:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/GOALPad-mac \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/GOALPad-sim \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/GOALPad-device \
  CODE_SIGNING_ALLOWED=NO build
```

These commands validate compilation and linking only. The generic iOS build is
not physical-device validation.

## Build the pinned OpenGOAL ARM64 host baseline

```sh
cmake -S OpenGOAL -B /private/tmp/GOALPad-opengoal-build \
  --preset=Release-macos-arm64-clang \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3

cmake --build /private/tmp/GOALPad-opengoal-build --target gk goalc-test -j 12

ln -s "$PWD/OpenGOAL" /private/tmp/GOALPad-opengoal-build/data

/private/tmp/GOALPad-opengoal-build/goalc-test \
  --gtest_filter='ARM64EmitterIntegerMath.*:CodeTester.*arm64'
```

This is an experimental ARM64 macOS host baseline. It does not prove that
OpenGOAL can execute GOAL code on ARM64 or iPadOS.

The `data` symlink is local build state. It lets OpenGOAL's test executable find
the pinned source tree when the build directory is outside the repository.

## Physical iPad validation

A signed physical-device build must omit `CODE_SIGNING_ALLOWED=NO` and use a
paired iPad destination:

```sh
xcodebuild -quiet -project GOALPad.xcodeproj -scheme GOALPad \
  -configuration Debug \
  -destination 'platform=iOS,id=<device-udid>' \
  -derivedDataPath /private/tmp/GOALPad-physical build
```

Record build, install, launch, and runtime-log results separately. Simulator or
generic-device success must not be reported as physical-device compatibility.
