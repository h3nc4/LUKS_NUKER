FROM debian:stable-slim AS builder
RUN apt-get update && \
	DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --no-install-recommends \
	bc \
	binutils \
	bison \
	bzip2 \
	cmake \
	cpio \
	dwarves \
	flex \
	gawk \
	gcc \
	gdb \
	git \
	gnupg2 \
	gperf \
	grub-common \
	grub-pc-bin \
	gzip \
	libblkid-dev \
	libdevmapper-dev \
	libelf-dev \
	libjson-c-dev \
	libncurses5-dev \
	libpopt-dev \
	libssh-dev \
	libssl-dev \
	make \
	openssl \
	pahole \
	perl-base \
	pkg-config \
	python3 \
	python3-pexpect \
	rsync \
	tar \
	texinfo \
	uuid-dev \
	xorriso \
	xz-utils \
	&& \
	apt-get clean

FROM builder AS kernel-headers
WORKDIR /kernel
ADD https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.13.1.tar.xz /kernel/
RUN tar --strip-components=1 -xf linux-6.13.1.tar.xz && \
	make mrproper && \
	make headers_install INSTALL_HDR_PATH=/kernel/built-headers

FROM builder AS glibc-builder
WORKDIR /glibc
COPY --from=kernel-headers /kernel/built-headers/include /usr/local/include
ADD https://ftp.gnu.org/gnu/glibc/glibc-2.41.tar.xz /glibc/
RUN tar --strip-components=1 -xf glibc-2.41.tar.xz && \
	mkdir build && cd build && \
	../configure --prefix=/ \
		--libdir=/lib \
		--sysconfdir=/etc \
		--disable-werror \
		--enable-kernel=6.13 && \
	make -j$(nproc) && \
	make install DESTDIR=/stage

RUN mkdir -p /stage/lib64 && \
	cd /stage/lib64 && \
	ln -s ../lib/ld-linux-x86-64.so.2 && \
	cd /stage/lib && \
	ln -s . x86_64-linux-gnu

FROM builder AS eudev-builder
WORKDIR /eudev
COPY --from=kernel-headers /kernel/built-headers/include /usr/local/include
ADD https://github.com/eudev-project/eudev/releases/download/v3.2.14/eudev-3.2.14.tar.gz /eudev/
RUN tar --strip-components=1 -xf eudev-3.2.14.tar.gz && \
	mkdir build && cd build && \
	../configure --with-rootprefix=/ \
		--libdir=/lib \
		--sysconfdir=/etc && \
	make -j$(nproc) && \
	make install DESTDIR=/stage

FROM builder AS selinux-builder
WORKDIR /selinux
COPY --from=kernel-headers /kernel/built-headers/include /usr/local/include
ADD https://github.com/SELinuxProject/selinux/releases/download/3.8/libsepol-3.8.tar.gz /selinux/
RUN tar xf libsepol-3.8.tar.gz && \
	cd libsepol-3.8/ && \
	make -j$(nproc) && \
	make install DESTDIR=/stage
ADD https://github.com/SELinuxProject/selinux/releases/download/3.8/libselinux-3.8.tar.gz /selinux/
RUN tar xf libselinux-3.8.tar.gz && \
	cd libselinux-3.8 && \
	make -j$(nproc) && \
	make install DESTDIR=/stage

FROM builder AS pcre2-builder
WORKDIR /pcre2
COPY --from=kernel-headers /kernel/built-headers/include /usr/local/include
ADD https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.45/pcre2-10.45.tar.gz /pcre2/
RUN tar --strip-components=1 -xf pcre2-10.45.tar.gz && \
	./configure --prefix=/ --enable-utf --enable-unicode-properties --enable-pcre2-8 && \
	make -j$(nproc) && \
	make install DESTDIR=/stage

FROM builder AS lvm2-builder
WORKDIR /lvm2
COPY --from=kernel-headers /kernel/built-headers/include /usr/local/include
ADD https://sourceware.org/ftp/lvm2/LVM2.2.03.30.tgz /lvm2/
RUN tar --strip-components=1 -xf LVM2.2.03.30.tgz && \
	./configure --prefix=/ --with-libdir=/lib && \
	make -j$(nproc) libdm && \
	make -C libdm install DESTDIR=/stage

RUN cd /stage/lib && \
	ln -s libdevmapper.so.1.02 libdevmapper.so.1.02.1

FROM builder AS popt-builder
WORKDIR /popt
COPY --from=kernel-headers /kernel/built-headers/include /usr/local/include
ADD https://ftp.osuosl.org/pub/rpm/popt/releases/popt-1.x/popt-1.19.tar.gz /popt/
RUN tar --strip-components=1 -xf popt-1.19.tar.gz && \
	./configure --prefix=/ --disable-static && \
	make -j$(nproc) && \
	make install DESTDIR=/stage

FROM builder AS openssl-builder
WORKDIR /openssl
ADD https://github.com/openssl/openssl/releases/download/openssl-3.4.0/openssl-3.4.0.tar.gz /openssl/
RUN tar --strip-components=1 -xf openssl-3.4.0.tar.gz && \
	./config --prefix=/ --openssldir=/etc/ssl --libdir=lib shared && \
	make -j$(nproc) && \
	make install DESTDIR=/stage

FROM builder AS jsonc-builder
WORKDIR /json-c
ADD https://s3.amazonaws.com/json-c_releases/releases/json-c-0.18.tar.gz /json-c/
RUN tar --strip-components=1 -xf json-c-0.18.tar.gz && \
	cmake -DCMAKE_INSTALL_PREFIX=/ \
		-DCMAKE_INSTALL_LIBDIR=/lib \
		-DCMAKE_BUILD_TYPE=Release  \
		-DBUILD_STATIC_LIBS=OFF && \
	make -j$(nproc) && \
	make install DESTDIR=/stage

FROM builder AS kernel-builder
WORKDIR /kernel
ADD https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.13.1.tar.xz /kernel/
RUN tar --strip-components=1 -xf linux-6.13.1.tar.xz && \
	make defconfig && \
	./scripts/config --file .config --set-str LOCALVERSION "-luksnuker" && \
	./scripts/config --file .config --enable CONFIG_DM_CRYPT && \
	./scripts/config --file .config --enable CONFIG_CRYPTO_AES && \
	./scripts/config --file .config --enable CONFIG_CRYPTO_AES_X86_64 && \
	./scripts/config --file .config --enable CONFIG_CRYPTO_XTS && \
	make -j$(nproc) bzImage

RUN mkdir -p /stage && \
	mv /kernel/arch/x86/boot/bzImage /stage/

FROM builder AS utils-builder
WORKDIR /util-linux
COPY --from=kernel-headers /kernel/built-headers/include /usr/local/include
ADD https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.39/util-linux-2.39.4.tar.xz /util-linux/
RUN tar --strip-components=1 -xf util-linux-2.39.4.tar.xz && \
	./configure && \
	make -j$(nproc) && \
	make DESTDIR=/stage install

FROM builder AS cryptsetup-builder
WORKDIR /cryptsetup
ADD https://www.kernel.org/pub/linux/utils/cryptsetup/v2.7/cryptsetup-2.7.5.tar.xz /cryptsetup/
RUN tar --strip-components=1 -xf cryptsetup-2.7.5.tar.xz && \
	./configure --prefix=/ --disable-asciidoc && \
	make -j$(nproc) && \
	make install DESTDIR=/stage

FROM builder AS busybox-builder
WORKDIR /busybox
ADD https://busybox.net/downloads/busybox-1.36.1.tar.bz2 /busybox/
RUN tar --strip-components=1 -xf busybox-1.36.1.tar.bz2 && \
	make defconfig && \
	make -j$(nproc) install CONFIG_PREFIX=/stage

FROM builder AS dash-builder
WORKDIR /dash
ADD http://gondor.apana.org.au/~herbert/dash/files/dash-0.5.12.tar.gz /dash/
RUN tar --strip-components=1 -xf dash-0.5.12.tar.gz && \
	./configure && \
	make -j$(nproc) && \
	make install

RUN mkdir -p /stage/bin && \
	mv /dash/src/dash /stage/bin/

FROM builder AS final-builder
WORKDIR /rootfs
COPY bin/init ./init
COPY cfg/inittab ./etc/inittab
COPY bin/nuke ./bin/nuke
RUN chmod +x ./init && \
	mkdir -p bin sbin dev proc sys tmp var etc run

COPY --from=glibc-builder /stage/ ./
COPY --from=eudev-builder /stage/ ./
COPY --from=selinux-builder /stage/ ./
COPY --from=pcre2-builder /stage/ ./
COPY --from=lvm2-builder /stage/ ./
COPY --from=popt-builder /stage/ ./
COPY --from=openssl-builder /stage/ ./
COPY --from=jsonc-builder /stage/ ./
COPY --from=utils-builder /stage/ ./
COPY --from=cryptsetup-builder /stage/ ./
COPY --from=busybox-builder /stage/ ./
COPY --from=dash-builder /stage/ ./
COPY --from=kernel-builder /stage/ ./

RUN cd bin && rm -f sh && ln -s dash sh && ln -s busybox init && cd - && \
	find . | cpio -o -H newc | gzip -9 >/initrd.img

CMD ["cp", "/initrd.img", "/rootfs/bzImage", "/output/"]
