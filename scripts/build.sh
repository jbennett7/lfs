#!/bin/bash

#exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash

function FAIL {
  logger $1
  echo $1
  exit 1
}

set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(scripts/config.guess)
PATH=/tools/bin:/bin:/usr/bin:${PATH}
BUILD=$(pwd)/build
SOURCES=${LFS}/sources
#export LFS LC_ALL LFS_TGT PATH

function binutils_1 {
    package_path=$(find ${SOURCES} -type f -name "binutils*tar*")
    [ -z ${package_path} ] && FAIL "no package in path."
    cd ${BUILD}
    package_dir=$(tar tf ${package_path} | sed -e 's@^\([^/]*\).*$@\1@')
    tar xf ${package_path}
    cd ${package_dir}
    mkdir -v build
    cd build
    ../configure --prefix=/tools \
                 --with-sysroot=${LFS} \
                 --with-lib-path=/tools/lib \
                 --target=${LFS_TGT} \
                 --disable-nls \
                 --disable-werror
    
    make -j4 2> make.error.log &&
    case $(uname -m) in
        x86_64)
            mkdir -v /tools/lib && ln -sv lib /tools/lib64
        ;;
    esac &&
    make install || FAIL "binutils failed to install"
}

function gcc_1 {
    package_path=$(find ${SOURCES} -type f -name "gcc*tar*")
    [ -z ${package_path} ] && FAIL "no package in path."
    cd ${BUILD}
    package_dir=$(tar tf ${package_path} | sed -e 's@^\([^/]*\).*$@\1@')
    tar xf ${package_path}
    cd ${package_dir}
    for p in mpfr gmp mpc;do
        tar xf $(find $LFS/sources -type f -name "$p*")
        mv -v $(find . -maxdepth 1 -type d -name "$p*") $p
    done
    ls
    for file in gcc/config/{linux,i386/linux{,64}}.h
    do
        cp -uv $file{,.orig}
        sed -e 's@/lib/ld@/tools&@g' \
            -e 's@/usr@/tools@g' $file.orig > $file
        echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
        touch $file.orig
    done
    case $(uname -m) in
        x86_64)
            sed -e '/m64=/s/lib64/lib/' \
                -i.orig gcc/config/i386/t-linux64
        ;;
    esac
    mkdir -p build
    cd build
    ../configure                                   \
    --target=${LFS_TGT}                            \
    --prefix=/tools                                \
    --with-sysroot=${LFS}                          \
    --with-newlib                                  \
    --without-headers                              \
    --with-local-prefix=/tools                     \
    --with-native-system-header-dir=/tools/include \
    --disable-nls                                  \
    --disable-shared                               \
    --disable-multilib                             \
    --disable-decimal-float                        \
    --disable-threads                              \
    --disable-libatomic                            \
    --disable-libgomp                              \
    --disable-libitm                               \
    --disable-libmpx                               \
    --disable-libsanitizer                         \
    --disable-libquadmath                          \
    --disable-libssp                               \
    --disable-libvtv                               \
    --disable-libcilkrts                           \
    --disable-libstdc++-v3                         \
    --enable-languages=c,c++
    make -j4 2> make.err.log &&
    make install
}

function linux_headers {
    cd ${BUILD}
    tar xf ${SOURCES}/linux-4.9.9.tar.xz
    cd linux-4.9.9
    make mrproper
    make INSTALL_HDR_PATH=dest headers_install
    cp -rv dest/include/* /tools/include
}

function glibc {
    cd ${BUILD}
    tar xf ${SOURCES}/glibc-2.25.tar.xz
    cd glibc-2.25
    mkdir -v build
    cd build
    ../configure \
        --prefix=/tools \
        --host=${LFS_TGT} \
        --build=$(../scripts/config.guess) \
        --enable-kernel=2.6.32 \
        --with-headers=/tools/include \
        libc_cv_forced_unwind=yes \
        libc_cv_c_cleanup=yes
    make -j4 2> make.error.log &&
    make install

    echo "Testing"
    echo 'init main(){}' > dummy.c
    $LFS_TGT-gcc dummy.c
    readelf -l a.out | grep ': /tools'
}

[ ! -d ${BUILD} ] && mkdir -vp ${BUILD}
case "${1}" in
    display_target)
        echo "${LFS_TGT}"
    ;;
    binutils_1)
        binutils_1
    ;;
    gcc_1)
        gcc_1
    ;;
    linux_headers)
        linux_headers
    ;;
    glibc)
        glibc
    ;;
    build_all)
        binutils_1
        gcc_1
        linux_headers
        glibc
    ;;
    marker)
        binutils_1
        gcc_1
    ;;
    *)
        sed -ne '/^case/,/^esac/s/  *\([_0-9a-z][_0-9a-z]*\))$/\1/p' ${0}
    ;;
esac
