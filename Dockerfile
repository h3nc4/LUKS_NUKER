FROM debian:stable-slim AS builder
RUN apt-get update && \
	DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --no-install-recommends \
	bc binutils bison bzip2 cpio dwarves flex gcc git gnupg2 grub-pc-bin grub-common gzip \
	libelf-dev libncurses5-dev libssl-dev make openssl pahole perl-base rsync tar xorriso xz-utils \
	&& \
	apt-get clean

FROM builder AS kernel-builder
WORKDIR /kernel
ADD https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.13.1.tar.xz /kernel/
RUN tar --strip-components=1 -xf linux-6.13.1.tar.xz && \
	./scripts/config --file .config --set-str LOCALVERSION "-luksnuker" && \
	make defconfig && \
	make -j$(nproc) bzImage

FROM builder AS busybox-builder
WORKDIR /busybox
ADD https://busybox.net/downloads/busybox-1.36.1.tar.bz2 /busybox/
RUN tar --strip-components=1 -xf busybox-1.36.1.tar.bz2 && \
	make defconfig && \
	sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' .config && \
	make -j$(nproc) install

FROM builder AS dash-builder
WORKDIR /dash
ADD http://gondor.apana.org.au/~herbert/dash/files/dash-0.5.12.tar.gz /dash/
RUN tar --strip-components=1 -xf dash-0.5.12.tar.gz && \
	./configure --enable-static && \
	make -j$(nproc) && \
	make install

FROM builder AS final-builder
WORKDIR /rootfs
COPY configs/init ./init
RUN chmod +x ./init && \
	mkdir -p bin sbin dev proc sys tmp var etc

COPY --from=busybox-builder /busybox/_install/bin/ bin/
RUN rm bin/sh
COPY --from=dash-builder /dash/src/dash bin/
COPY --from=kernel-builder /kernel/arch/x86/boot/bzImage ./bzImage

RUN cd bin && ln -s dash sh
RUN find . | cpio -o -H newc | gzip >/initrd.img

CMD ["cp", "/initrd.img", "/rootfs/bzImage", "/output/"]
