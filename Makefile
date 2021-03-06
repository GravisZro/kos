ifneq ($(DEBUG),true)
  QUIET:=@
endif

ifndef PLATFORM
  PLATFORM:=dreamcast
endif

ifndef ARCH
  ARCH:=sh-elf
endif

ifndef INSTALL_PATH
  INSTALL_PATH:=/usr/local
endif

OBJS:=$(shell "sh" "filelist.sh")

TARGET:=libkos.a

DEFINES:= \
        -D_arch_$(PLATFORM) \
        -DPLATFORM="$(PLATFORM)" \
	-D__DREAMCAST__

CFLAGS:=$(DEFINES) \
	-std=c11 \
        -Wall -Wextra \
        -g \
        -fno-builtin \
        -fno-strict-aliasing \
        -fomit-frame-pointer \
        -ffunction-sections \
        -fdata-sections

CFLAGS+=-Icommon/include \
	-Iaddons/include \
	-I$(PLATFORM)/include \
	-I$(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include

# out-of-band includes
CFLAGS+=-Icommon/net \
	\
	-Iaddons/libppp \
	-Iaddons/libkosutils \
	-Iaddons/libkosext2fs \
	\
	-Idreamcast/hardware/pvr \
	-Idreamcast/hardware/modem \
	-Idreamcast/kernel


GCCPREFIX:=$(PLATFORM)-$(shell echo $(ARCH) | cut -d '-' -f 1)

$(TARGET): $(OBJS)
	@echo Linking: $@
	$(QUIET) $(GCCPREFIX)-ar rcs $@ $(OBJS)

install_headers:
	@echo "Installing headers..."
	$(QUIET) mkdir -p $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/kos
	$(QUIET) mkdir -p $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/sys
	$(QUIET) cp -R common/include/kos           $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/
	$(QUIET) cp -R common/include/netinet       $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/
	$(QUIET) cp -R common/include/arpa          $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/
	$(QUIET) cp -R $(PLATFORM)/include          $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/
	$(QUIET) cp -R addons/include/kos           $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/
	$(QUIET) cp common/include/kos.h            $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/
	$(QUIET) cp common/include/pthread.h        $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/
	$(QUIET) cp common/include/sys/uio.h        $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/sys/
	$(QUIET) cp common/include/sys/socket.h     $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/sys/
	$(QUIET) cp common/include/sys/_pthread.h   $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/sys/
	$(QUIET) cp common/include/sys/sched.h      $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/sys/
#	$(QUIET) cp -R common/include/*		$(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/
#	$(QUIET) cp -R addons/include/*		$(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/include/

install: $(TARGET) install_headers
	@echo "Installing library..."
	$(QUIET) cp $(TARGET)                       $(INSTALL_PATH)/$(PLATFORM)/$(ARCH)/lib/

clean:
	$(QUIET) rm -f $(OBJS) $(TARGET)

common/libc/c11/%.o: common/libc/c11/%.c
	@echo Building: $@
	$(QUIET) $(GCCPREFIX)-gcc -std=c11 $(CFLAGS) -c $< -o $@

%.o: %.c
	@echo Building: $@
	$(QUIET) $(GCCPREFIX)-gcc $(CFLAGS) -c $< -o $@

%.o: %.s
	@echo Building: $@
	$(QUIET) $(GCCPREFIX)-as -little $< -o $@

%.o: %.S
	@echo Building: $@
	$(QUIET) $(GCCPREFIX)-as -little $< -o $@

hexdump: $(infile)
	$(QUIET) od -t x1 $(infile) | sed -e "s/[0-9a-fA-F]\{7,9\}//" -e "s/ \([0-9a-fA-F][0-9a-fA-F]\)/0x\1, /g" >> $(outfile)

dreamcast/sound/snd_stream_drv.h: dreamcast/sound/snd_stream_drv.bin
	$(QUIET) echo "unsigned char aica_fw[] = {" >> $@
	$(QUIET) make hexdump -e infile=$< -e outfile=$@ -e DEBUG=$(DEBUG)
	$(QUIET) echo "};\n" >> $@

dreamcast/sound/snd_stream_drv.bin:
	@echo Building ARM sound driver...
	$(QUIET) make -C dreamcast/sound/arm -e ARCH=arm-eabi -e PLATFORM=$(PLATFORM) -e DEBUG=$(DEBUG)
	$(QUIET) make -C dreamcast/sound/arm -e ARCH=arm-eabi -e PLATFORM=$(PLATFORM) -e DEBUG=$(DEBUG) install
	$(QUIET) make -C dreamcast/sound/arm -e ARCH=arm-eabi -e PLATFORM=$(PLATFORM) -e DEBUG=$(DEBUG) clean

dreamcast/sound/snd_stream_drv.o: dreamcast/sound/snd_stream_drv.bin
	@echo "Transforming... $< to $@"
	$(QUIET) echo ".section .rodata; .align 2; " | $(GCCPREFIX)-as -o tmp3.bin
	$(QUIET) echo "SECTIONS { .rodata : { _snd_stream_drv = .; *(.data); _snd_stream_drv_end = .; } }" > tmp1.ld
	$(QUIET) $(GCCPREFIX)-ld --no-warn-mismatch --format binary --oformat elf32-shl $< --format elf32-shl tmp3.bin -o tmp2.bin -r -EL -T tmp1.ld
	$(QUIET) $(GCCPREFIX)-objcopy --set-section-flags .rodata=alloc,load,data,readonly tmp2.bin $@
	$(QUIET) rm -f tmp1.ld tmp2.bin tmp3.bin

dreamcast/kernel/banner.o: dreamcast/kernel/banner.c
	@echo Generating banner data...
	$(eval VERSION:=Git revision $(shell git rev-list --full-history --all --abbrev-commit | head -1))
	$(eval HOSTNAME:=$(shell hostname -f))
	$(eval BANNER:=KallistiOS $(VERSION): $(shell date)\n  $(shell whoami)@$(HOSTNAME))
	$(eval LICENSE:=$(shell cat LICENSE | sed -e "s/$$/\\\\n/" -e "s/\\\"/\\\\\"/g"))
	$(eval AUTHORS:=$(shell cat AUTHORS | sed -e "s/$$/\\\\n/" -e "s/\\\"/\\\\\"/g"))
	@echo Building: $@
	$(QUIET) $(GCCPREFIX)-gcc $(CFLAGS) -DBANNER="\"$(BANNER)\"" -DLICENSE="\"$(LICENSE)\"" -DAUTHORS="\"$(AUTHORS)\"" -c $< -o $@

# generative
common/kernel_export_stubs.c: common/exports.txt
	sh genexportstubs.sh $< $@

common/kernel_export_stubs.o: common/kernel_export_stubs.c
	@echo Building: $@
	$(QUIET) $(GCCPREFIX)-gcc $(CFLAGS) -c $< -o $@
	@echo Cleaning up generated file: $<
	$(QUIET) echo rm $<

dreamcast/arch_export_stubs.c: dreamcast/exports.txt
	sh genexportstubs.sh $< $@

dreamcast/arch_export_stubs.o: dreamcast/arch_export_stubs.c
	@echo Building: $@
	$(QUIET) $(GCCPREFIX)-gcc $(CFLAGS) -c $< -o $@
	@echo Cleaning up generated file: $<
	$(QUIET) echo rm $<

common/exports/kernel_exports.c: common/exports.txt
	sh genexports.sh $< $@ kernel_symtab

common/exports/kernel_exports.o: common/exports/kernel_exports.c
	@echo Building: $@
	$(QUIET) $(GCCPREFIX)-gcc $(CFLAGS) -c $< -o $@
	@echo Cleaning up generated file: $<
	$(QUIET) echo rm $<

dreamcast/kernel/arch_exports.c: dreamcast/exports.txt
	sh genexports.sh $< $@ arch_symtab

dreamcast/kernel/arch_exports.o: dreamcast/kernel/arch_exports.c
	@echo Building: $@
	$(QUIET) $(GCCPREFIX)-gcc $(CFLAGS) -c $< -o $@
	@echo Cleaning up generated file: $<
	$(QUIET) echo rm $<
