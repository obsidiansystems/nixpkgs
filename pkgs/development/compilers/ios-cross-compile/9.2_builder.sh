# -*- shell-script -*-
source $stdenv/setup

LC_ALL=C

triple="$arch-apple-darwin11"
platform="$(uname -s)"

mkdir -p "$out"
mkdir -p "$out"/bin

cp -r --no-preserve=mode "$ldid" "$out"/ldid
cp -r --no-preserve=mode "$cctools_port" "$out"/cctools
cp -r --no-preserve=mode "$sdk" "$out"/"$sdkName"

triple="$(printf "$triple" "$2")"

printf "\nbuilding wrapper\n"

printf "int main(){return 0;}" | clang -xc -O2 -o "$out"/bin/dsymutil -

clang -O2 -std=c99 $alt_wrapper \
    -DTARGET_CPU=$(printf '"%s"' "$arch") \
    -DNIX_APPLE_HDRS=$(
  printf '"%s"' "-I$out/$sdkName/usr/include"
    ) \
    -DNIX_APPLE_FRAMEWORKS=$(
  printf '"%s"' "$out/$sdkName/System/Library/Frameworks"
    ) \
    -DNIX_APPLE_PRIV_FRAMEWORKS=$(
  printf '"%s"' "$out/$sdkName/System/Library/PrivateFrameworks"
    ) \
    -DOS_VER_MIN=$(printf '"%s"' "7.1") \
    -o "$out/bin/$triple-clang"

cp "$out"/bin/"$triple"-clang "$out"/bin/"$triple"-clang++

printf "\nbuilding ldid\n"
(cd "$out"/ldid; make INSTALLPREFIX="$out" -j4 install)

printf "\nbuilding cctools / ld64\n"
(cd "$out"/cctools/cctools; chmod +x autogen.sh; ./autogen.sh; ./configure --target="$triple" --prefix="$out"; make -j4; make install &>/dev/null)

rm -rf "$out"/cctools
rm -rf "$out"/ldid
