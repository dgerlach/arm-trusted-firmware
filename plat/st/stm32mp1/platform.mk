#
# Copyright (c) 2015-2022, ARM Limited and Contributors. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#

ARM_CORTEX_A7		:=	yes
ARM_WITH_NEON		:=	yes
BL2_AT_EL3		:=	1
USE_COHERENT_MEM	:=	0

STM32MP_EARLY_CONSOLE	?=	0
STM32MP_UART_BAUDRATE	?=	115200

# Allow TF-A to concatenate BL2 & BL32 binaries in a single file,
# share DTB file between BL2 and BL32
# If it is set to 0, then FIP is used
STM32MP_USE_STM32IMAGE	?=	0

# Please don't increment this value without good understanding of
# the monotonic counter
STM32_TF_VERSION	?=	0

# Enable dynamic memory mapping
PLAT_XLAT_TABLES_DYNAMIC :=	1

# Default Device tree
DTB_FILE_NAME		?=	stm32mp157c-ev1.dtb

STM32MP13		?=	0
STM32MP15		?=	0

ifeq ($(STM32MP13),1)
ifeq ($(STM32MP15),1)
$(error Cannot enable both flags STM32MP13 and STM32MP15)
endif
STM32MP13		:=	1
STM32MP15		:=	0
else ifeq ($(STM32MP15),1)
STM32MP13		:=	0
STM32MP15		:=	1
else ifneq ($(findstring stm32mp13,$(DTB_FILE_NAME)),)
STM32MP13		:=	1
STM32MP15		:=	0
else ifneq ($(findstring stm32mp15,$(DTB_FILE_NAME)),)
STM32MP13		:=	0
STM32MP15		:=	1
endif

ifeq ($(STM32MP13),1)
# DDR controller with single AXI port and 16-bit interface
STM32MP_DDR_DUAL_AXI_PORT:=	0
STM32MP_DDR_32BIT_INTERFACE:=	0

# STM32 image header version v2.0
STM32_HEADER_VERSION_MAJOR:=	2
STM32_HEADER_VERSION_MINOR:=	0
endif

ifeq ($(STM32MP15),1)
# DDR controller with dual AXI port and 32-bit interface
STM32MP_DDR_DUAL_AXI_PORT:=	1
STM32MP_DDR_32BIT_INTERFACE:=	1

# STM32 image header version v1.0
STM32_HEADER_VERSION_MAJOR:=	1
STM32_HEADER_VERSION_MINOR:=	0
endif

# STM32 image header binary type for BL2
STM32_HEADER_BL2_BINARY_TYPE:=	0x10

ifeq ($(AARCH32_SP),sp_min)
# Disable Neon support: sp_min runtime may conflict with non-secure world
TF_CFLAGS		+=	-mfloat-abi=soft
endif

TF_CFLAGS		+=	-Wsign-compare
TF_CFLAGS		+=	-Wformat-signedness

# Not needed for Cortex-A7
WORKAROUND_CVE_2017_5715:=	0
WORKAROUND_CVE_2022_23960:=	0

ifeq (${PSA_FWU_SUPPORT},1)
ifneq (${STM32MP_USE_STM32IMAGE},1)
# Number of banks of updatable firmware
NR_OF_FW_BANKS			:=	2
NR_OF_IMAGES_IN_FW_BANK		:=	1

# Number of TF-A copies in the device
STM32_TF_A_COPIES		:=	2
STM32_BL33_PARTS_NUM		:=	2
STM32_RUNTIME_PARTS_NUM		:=	4
else
$(error FWU Feature enabled only with FIP images)
endif
else
# Number of TF-A copies in the device
STM32_TF_A_COPIES		:=	2
STM32_BL33_PARTS_NUM		:=	1
ifeq ($(AARCH32_SP),optee)
STM32_RUNTIME_PARTS_NUM		:=	3
else ifeq ($(STM32MP_USE_STM32IMAGE),1)
STM32_RUNTIME_PARTS_NUM		:=	0
else
STM32_RUNTIME_PARTS_NUM		:=	1
endif
endif
PLAT_PARTITION_MAX_ENTRIES	:=	$(shell echo $$(($(STM32_TF_A_COPIES) + \
							 $(STM32_BL33_PARTS_NUM) + \
							 $(STM32_RUNTIME_PARTS_NUM))))

# Boot devices
STM32MP_EMMC		?=	0
STM32MP_SDMMC		?=	0
STM32MP_RAW_NAND	?=	0
STM32MP_SPI_NAND	?=	0
STM32MP_SPI_NOR		?=	0
STM32MP_EMMC_BOOT	?=	0

# Serial boot devices
STM32MP_USB_PROGRAMMER	?=	0
STM32MP_UART_PROGRAMMER	?=	0

# Device tree
ifeq ($(STM32MP13),1)
BL2_DTSI		:=	stm32mp13-bl2.dtsi
FDT_SOURCES		:=	$(addprefix ${BUILD_PLAT}/fdts/, $(patsubst %.dtb,%-bl2.dts,$(DTB_FILE_NAME)))
else
ifeq ($(STM32MP_USE_STM32IMAGE),1)
ifeq ($(AARCH32_SP),optee)
BL2_DTSI		:=	stm32mp15-bl2.dtsi
FDT_SOURCES		:=	$(addprefix ${BUILD_PLAT}/fdts/, $(patsubst %.dtb,%-bl2.dts,$(DTB_FILE_NAME)))
else
FDT_SOURCES		:=	$(addprefix fdts/, $(patsubst %.dtb,%.dts,$(DTB_FILE_NAME)))
endif
else
BL2_DTSI		:=	stm32mp15-bl2.dtsi
FDT_SOURCES		:=	$(addprefix ${BUILD_PLAT}/fdts/, $(patsubst %.dtb,%-bl2.dts,$(DTB_FILE_NAME)))
ifeq ($(AARCH32_SP),sp_min)
BL32_DTSI		:=	stm32mp15-bl32.dtsi
FDT_SOURCES		+=	$(addprefix ${BUILD_PLAT}/fdts/, $(patsubst %.dtb,%-bl32.dts,$(DTB_FILE_NAME)))
endif
endif
endif

$(eval DTC_V = $(shell $(DTC) -v | awk '{print $$NF}'))
$(eval DTC_VERSION = $(shell printf "%d" $(shell echo ${DTC_V} | cut -d- -f1 | sed "s/\./0/g")))
DTC_CPPFLAGS		+=	${INCLUDES}
DTC_FLAGS		+=	-Wno-unit_address_vs_reg
ifeq ($(shell test $(DTC_VERSION) -ge 10601; echo $$?),0)
DTC_FLAGS		+=	-Wno-interrupt_provider
endif

# Macros and rules to build TF binary
STM32_TF_ELF_LDFLAGS	:=	--hash-style=gnu --as-needed
STM32_TF_STM32		:=	$(addprefix ${BUILD_PLAT}/tf-a-, $(patsubst %.dtb,%.stm32,$(DTB_FILE_NAME)))
STM32_TF_LINKERFILE	:=	${BUILD_PLAT}/stm32mp1.ld

ASFLAGS			+= -DBL2_BIN_PATH=\"${BUILD_PLAT}/bl2.bin\"
ifeq ($(AARCH32_SP),sp_min)
# BL32 is built only if using SP_MIN
BL32_DEP		:= bl32
ASFLAGS			+= -DBL32_BIN_PATH=\"${BUILD_PLAT}/bl32.bin\"
endif

# Variables for use with stm32image
STM32IMAGEPATH		?= tools/stm32image
STM32IMAGE		?= ${STM32IMAGEPATH}/stm32image${BIN_EXT}
STM32IMAGE_SRC		:= ${STM32IMAGEPATH}/stm32image.c

ifneq (${STM32MP_USE_STM32IMAGE},1)
FIP_DEPS		+=	dtbs
STM32MP_HW_CONFIG	:=	${BL33_CFG}
STM32MP_FW_CONFIG_NAME	:=	$(patsubst %.dtb,%-fw-config.dtb,$(DTB_FILE_NAME))
STM32MP_FW_CONFIG	:=	${BUILD_PLAT}/fdts/$(STM32MP_FW_CONFIG_NAME)
ifneq (${AARCH32_SP},none)
FDT_SOURCES		+=	$(addprefix fdts/, $(patsubst %.dtb,%.dts,$(STM32MP_FW_CONFIG_NAME)))
endif
# Add the FW_CONFIG to FIP and specify the same to certtool
$(eval $(call TOOL_ADD_PAYLOAD,${STM32MP_FW_CONFIG},--fw-config))
# Add the HW_CONFIG to FIP and specify the same to certtool
$(eval $(call TOOL_ADD_PAYLOAD,${STM32MP_HW_CONFIG},--hw-config))
ifeq ($(AARCH32_SP),sp_min)
STM32MP_TOS_FW_CONFIG	:= $(addprefix ${BUILD_PLAT}/fdts/, $(patsubst %.dtb,%-bl32.dtb,$(DTB_FILE_NAME)))
$(eval $(call TOOL_ADD_PAYLOAD,${STM32MP_TOS_FW_CONFIG},--tos-fw-config))
else
# Add the build options to pack Trusted OS Extra1 and Trusted OS Extra2 images
# in the FIP if the platform requires.
ifneq ($(BL32_EXTRA1),)
$(eval $(call TOOL_ADD_IMG,BL32_EXTRA1,--tos-fw-extra1))
endif
ifneq ($(BL32_EXTRA2),)
$(eval $(call TOOL_ADD_IMG,BL32_EXTRA2,--tos-fw-extra2))
endif
endif
endif

# Enable flags for C files
$(eval $(call assert_booleans,\
	$(sort \
		PLAT_XLAT_TABLES_DYNAMIC \
		STM32MP_DDR_32BIT_INTERFACE \
		STM32MP_DDR_DUAL_AXI_PORT \
		STM32MP_EARLY_CONSOLE \
		STM32MP_EMMC \
		STM32MP_EMMC_BOOT \
		STM32MP_RAW_NAND \
		STM32MP_SDMMC \
		STM32MP_SPI_NAND \
		STM32MP_SPI_NOR \
		STM32MP_UART_PROGRAMMER \
		STM32MP_USB_PROGRAMMER \
		STM32MP_USE_STM32IMAGE \
		STM32MP13 \
		STM32MP15 \
)))

$(eval $(call assert_numerics,\
	$(sort \
		PLAT_PARTITION_MAX_ENTRIES \
		STM32_TF_A_COPIES \
		STM32_TF_VERSION \
		STM32MP_UART_BAUDRATE \
)))

$(eval $(call add_defines,\
	$(sort \
		PLAT_PARTITION_MAX_ENTRIES \
		PLAT_XLAT_TABLES_DYNAMIC \
		STM32_TF_A_COPIES \
		STM32_TF_VERSION \
		STM32MP_DDR_32BIT_INTERFACE \
		STM32MP_DDR_DUAL_AXI_PORT \
		STM32MP_EARLY_CONSOLE \
		STM32MP_EMMC \
		STM32MP_EMMC_BOOT \
		STM32MP_RAW_NAND \
		STM32MP_SDMMC \
		STM32MP_SPI_NAND \
		STM32MP_SPI_NOR \
		STM32MP_UART_BAUDRATE \
		STM32MP_UART_PROGRAMMER \
		STM32MP_USB_PROGRAMMER \
		STM32MP_USE_STM32IMAGE \
		STM32MP13 \
		STM32MP15 \
)))

# Include paths and source files
PLAT_INCLUDES		:=	-Iplat/st/common/include/
PLAT_INCLUDES		+=	-Iplat/st/stm32mp1/include/

ifeq (${STM32MP_USE_STM32IMAGE},1)
include common/fdt_wrappers.mk
else
include lib/fconf/fconf.mk
endif
include lib/libfdt/libfdt.mk

PLAT_BL_COMMON_SOURCES	:=	common/uuid.c						\
				plat/st/common/stm32mp_common.c				\
				plat/st/stm32mp1/stm32mp1_private.c

PLAT_BL_COMMON_SOURCES	+=	drivers/st/uart/aarch32/stm32_console.S

ifneq (${ENABLE_STACK_PROTECTOR},0)
PLAT_BL_COMMON_SOURCES	+=	plat/st/stm32mp1/stm32mp1_stack_protector.c
endif

include lib/xlat_tables_v2/xlat_tables.mk
PLAT_BL_COMMON_SOURCES	+=	${XLAT_TABLES_LIB_SRCS}

PLAT_BL_COMMON_SOURCES	+=	lib/cpus/aarch32/cortex_a7.S

PLAT_BL_COMMON_SOURCES	+=	drivers/arm/tzc/tzc400.c				\
				drivers/clk/clk.c					\
				drivers/delay_timer/delay_timer.c			\
				drivers/delay_timer/generic_delay_timer.c		\
				drivers/st/bsec/bsec2.c					\
				drivers/st/clk/stm32mp_clkfunc.c			\
				drivers/st/ddr/stm32mp_ddr.c				\
				drivers/st/ddr/stm32mp1_ddr_helpers.c			\
				drivers/st/gpio/stm32_gpio.c				\
				drivers/st/i2c/stm32_i2c.c				\
				drivers/st/iwdg/stm32_iwdg.c				\
				drivers/st/pmic/stm32mp_pmic.c				\
				drivers/st/pmic/stpmic1.c				\
				drivers/st/regulator/regulator_core.c			\
				drivers/st/regulator/regulator_fixed.c			\
				drivers/st/reset/stm32mp1_reset.c			\
				plat/st/common/stm32mp_dt.c				\
				plat/st/stm32mp1/stm32mp1_dbgmcu.c			\
				plat/st/stm32mp1/stm32mp1_helper.S			\
				plat/st/stm32mp1/stm32mp1_syscfg.c

ifeq ($(STM32MP13),1)
PLAT_BL_COMMON_SOURCES	+=	drivers/st/clk/clk-stm32-core.c				\
				drivers/st/clk/clk-stm32mp13.c
else
PLAT_BL_COMMON_SOURCES	+=	drivers/st/clk/stm32mp1_clk.c
endif

ifneq (${STM32MP_USE_STM32IMAGE},1)
BL2_SOURCES		+=	${FCONF_SOURCES} ${FCONF_DYN_SOURCES}

BL2_SOURCES		+=	drivers/io/io_fip.c					\
				plat/st/common/bl2_io_storage.c				\
				plat/st/common/stm32mp_fconf_io.c			\
				plat/st/stm32mp1/plat_bl2_mem_params_desc.c		\
				plat/st/stm32mp1/stm32mp1_fconf_firewall.c
else
BL2_SOURCES		+=	${FDT_WRAPPERS_SOURCES}

BL2_SOURCES		+=	drivers/io/io_dummy.c					\
				drivers/st/io/io_stm32image.c				\
				plat/st/common/bl2_stm32_io_storage.c			\
				plat/st/stm32mp1/plat_bl2_stm32_mem_params_desc.c	\
				plat/st/stm32mp1/stm32mp1_security.c
endif

ifeq (${PSA_FWU_SUPPORT},1)
include lib/zlib/zlib.mk
include drivers/fwu/fwu.mk

BL2_SOURCES		+=	$(ZLIB_SOURCES)
endif

BL2_SOURCES		+=	drivers/io/io_block.c					\
				drivers/io/io_mtd.c					\
				drivers/io/io_storage.c					\
				drivers/st/crypto/stm32_hash.c				\
				plat/st/stm32mp1/bl2_plat_setup.c


ifeq ($(STM32MP15),1)
BL2_SOURCES		+=	plat/st/common/stm32mp_auth.c
endif

ifneq ($(filter 1,${STM32MP_EMMC} ${STM32MP_SDMMC}),)
BL2_SOURCES		+=	drivers/mmc/mmc.c					\
				drivers/partition/gpt.c					\
				drivers/partition/partition.c				\
				drivers/st/io/io_mmc.c					\
				drivers/st/mmc/stm32_sdmmc2.c
endif

ifeq (${STM32MP_RAW_NAND},1)
$(eval $(call add_define_val,NAND_ONFI_DETECT,1))
BL2_SOURCES		+=	drivers/mtd/nand/raw_nand.c				\
				drivers/st/fmc/stm32_fmc2_nand.c
endif

ifeq (${STM32MP_SPI_NAND},1)
BL2_SOURCES		+=	drivers/mtd/nand/spi_nand.c
endif

ifeq (${STM32MP_SPI_NOR},1)
BL2_SOURCES		+=	drivers/mtd/nor/spi_nor.c
endif

ifneq ($(filter 1,${STM32MP_SPI_NAND} ${STM32MP_SPI_NOR}),)
BL2_SOURCES		+=	drivers/mtd/spi-mem/spi_mem.c				\
				drivers/st/spi/stm32_qspi.c
endif

ifneq ($(filter 1,${STM32MP_RAW_NAND} ${STM32MP_SPI_NAND}),)
BL2_SOURCES		+=	drivers/mtd/nand/core.c
endif

ifneq ($(filter 1,${STM32MP_RAW_NAND} ${STM32MP_SPI_NAND} ${STM32MP_SPI_NOR}),)
BL2_SOURCES		+=	plat/st/stm32mp1/stm32mp1_boot_device.c
endif

ifneq ($(filter 1,${STM32MP_UART_PROGRAMMER} ${STM32MP_USB_PROGRAMMER}),)
BL2_SOURCES		+=	drivers/io/io_memmap.c
endif

ifeq (${STM32MP_UART_PROGRAMMER},1)
BL2_SOURCES		+=	drivers/st/uart/stm32_uart.c				\
				plat/st/common/stm32cubeprogrammer_uart.c
endif

ifeq (${STM32MP_USB_PROGRAMMER},1)
#The DFU stack uses only one end point, reduce the USB stack footprint
$(eval $(call add_define_val,CONFIG_USBD_EP_NB,1U))
BL2_SOURCES		+=	drivers/st/usb/stm32mp1_usb.c				\
				drivers/usb/usb_device.c				\
				plat/st/common/stm32cubeprogrammer_usb.c		\
				plat/st/common/usb_dfu.c					\
				plat/st/stm32mp1/stm32mp1_usb_dfu.c
endif

BL2_SOURCES		+=	drivers/st/ddr/stm32mp_ddr_test.c			\
				drivers/st/ddr/stm32mp_ram.c				\
				drivers/st/ddr/stm32mp1_ddr.c				\
				drivers/st/ddr/stm32mp1_ram.c

BL2_SOURCES		+=	common/desc_image_load.c				\
				plat/st/stm32mp1/plat_image_load.c

BL2_SOURCES		+=	lib/optee/optee_utils.c

# Compilation rules
.PHONY: check_dtc_version stm32image clean_stm32image check_boot_device
.SUFFIXES:

all: check_dtc_version stm32image ${STM32_TF_STM32}

distclean realclean clean: clean_stm32image

bl2: check_boot_device

check_boot_device:
	@if [ ${STM32MP_EMMC} != 1 ] && \
	    [ ${STM32MP_SDMMC} != 1 ] && \
	    [ ${STM32MP_RAW_NAND} != 1 ] && \
	    [ ${STM32MP_SPI_NAND} != 1 ] && \
	    [ ${STM32MP_SPI_NOR} != 1 ] && \
	    [ ${STM32MP_UART_PROGRAMMER} != 1 ] && \
	    [ ${STM32MP_USB_PROGRAMMER} != 1 ]; then \
		echo "No boot device driver is enabled"; \
		false; \
	fi

stm32image: ${STM32IMAGE}

${STM32IMAGE}: ${STM32IMAGE_SRC}
	${Q}${MAKE} CPPFLAGS="" --no-print-directory -C ${STM32IMAGEPATH}

clean_stm32image:
	${Q}${MAKE} --no-print-directory -C ${STM32IMAGEPATH} clean

check_dtc_version:
	@if [ ${DTC_VERSION} -lt 10404 ]; then \
		echo "dtc version too old (${DTC_V}), you need at least version 1.4.4"; \
		false; \
	fi

ifeq ($(STM32MP_USE_STM32IMAGE)-$(AARCH32_SP),1-sp_min)
${BUILD_PLAT}/stm32mp1-%.o: ${BUILD_PLAT}/fdts/%.dtb plat/st/stm32mp1/stm32mp1.S bl2 ${BL32_DEP}
	@echo "  AS      stm32mp1.S"
	${Q}${AS} ${ASFLAGS} ${TF_CFLAGS} \
		-DDTB_BIN_PATH=\"$<\" \
		-c $(word 2,$^) -o $@
else
# Create DTB file for BL2
${BUILD_PLAT}/fdts/%-bl2.dts: fdts/%.dts fdts/${BL2_DTSI} | ${BUILD_PLAT} fdt_dirs
	@echo '#include "$(patsubst fdts/%,%,$<)"' > $@
	@echo '#include "${BL2_DTSI}"' >> $@

${BUILD_PLAT}/fdts/%-bl2.dtb: ${BUILD_PLAT}/fdts/%-bl2.dts

ifeq ($(AARCH32_SP),sp_min)
# Create DTB file for BL32
${BUILD_PLAT}/fdts/%-bl32.dts: fdts/%.dts fdts/${BL32_DTSI} | ${BUILD_PLAT} fdt_dirs
	@echo '#include "$(patsubst fdts/%,%,$<)"' > $@
	@echo '#include "${BL32_DTSI}"' >> $@

${BUILD_PLAT}/fdts/%-bl32.dtb: ${BUILD_PLAT}/fdts/%-bl32.dts
endif

${BUILD_PLAT}/stm32mp1-%.o: ${BUILD_PLAT}/fdts/%-bl2.dtb plat/st/stm32mp1/stm32mp1.S bl2
	@echo "  AS      stm32mp1.S"
	${Q}${AS} ${ASFLAGS} ${TF_CFLAGS} \
		-DDTB_BIN_PATH=\"$<\" \
		-c plat/st/stm32mp1/stm32mp1.S -o $@
endif

$(eval $(call MAKE_LD,${STM32_TF_LINKERFILE},plat/st/stm32mp1/stm32mp1.ld.S,bl2))

tf-a-%.elf: stm32mp1-%.o ${STM32_TF_LINKERFILE}
	@echo "  LDS     $<"
	${Q}${LD} -o $@ ${STM32_TF_ELF_LDFLAGS} -Map=$(@:.elf=.map) --script ${STM32_TF_LINKERFILE} $<

tf-a-%.bin: tf-a-%.elf
	${Q}${OC} -O binary $< $@
	@echo
	@echo "Built $@ successfully"
	@echo

tf-a-%.stm32: ${STM32IMAGE} tf-a-%.bin
	@echo
	@echo "Generate $@"
	$(eval LOADADDR = $(shell cat $(@:.stm32=.map) | grep RAM | awk '{print $$2}'))
	$(eval ENTRY = $(shell cat $(@:.stm32=.map) | grep "__BL2_IMAGE_START" | awk '{print $$1}'))
	${Q}${STM32IMAGE} -s $(word 2,$^) -d $@ \
		-l $(LOADADDR) -e ${ENTRY} \
		-v ${STM32_TF_VERSION} \
		-m ${STM32_HEADER_VERSION_MAJOR} \
		-n ${STM32_HEADER_VERSION_MINOR} \
		-b ${STM32_HEADER_BL2_BINARY_TYPE}
	@echo
