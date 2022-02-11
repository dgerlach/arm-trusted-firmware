#
# Copyright (c) 2017-2020, ARM Limited and Contributors. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#

# We don't use BL1 or BL2, so BL31 is the first image to execute
RESET_TO_BL31		:=	1
# Only one core starts up at first
COLD_BOOT_SINGLE_CPU	:=	1
# We can choose where a core starts executing
PROGRAMMABLE_RESET_ADDRESS:=	1

# ARM coherency is managed in hardware
WARMBOOT_ENABLE_DCACHE_EARLY :=	1

# A53 erratum for SoC. (enable them all)
ERRATA_A53_826319	:=	1
ERRATA_A53_835769	:=	1
ERRATA_A53_836870	:=	1
ERRATA_A53_843419	:=	1
ERRATA_A53_855873	:=	1
ERRATA_A53_1530924	:=	1

# A72 Erratum for SoC
ERRATA_A72_859971	:=	1
ERRATA_A72_1319367	:=	1

CRASH_REPORTING		:= 1
HANDLE_EA_EL3_FIRST	:= 1

# Split out RO data into a non-executable section
SEPARATE_CODE_AND_RODATA :=    1

# Generate a Position Independent Executable
ENABLE_PIE		:=	1

TI_16550_MDR_QUIRK	:=	1
$(eval $(call add_define,TI_16550_MDR_QUIRK))

K3_USART		:=	0
$(eval $(call add_define,K3_USART))

# Allow customizing the UART baud rate
K3_USART_BAUD		:=	115200
$(eval $(call add_define,K3_USART_BAUD))

# Enable system suspend modes
K3_PM_SYSTEM_SUSPEND	:=	0
$(eval $(call add_define,K3_PM_SYSTEM_SUSPEND))

# Libraries
include lib/xlat_tables_v2/xlat_tables.mk

PLAT_INCLUDES		+=	\
				-I${PLAT_PATH}/include			\
				-I${PLAT_PATH}/common/drivers/sec_proxy	\
				-I${PLAT_PATH}/common/drivers/ti_sci	\

K3_CONSOLE_SOURCES	+=	\
				drivers/ti/uart/aarch64/16550_console.S	\
				${PLAT_PATH}/common/k3_console.c	\

# Include GICv3 driver files
include drivers/arm/gic/v3/gicv3.mk

K3_GIC_SOURCES		+=	\
				${GICV3_SOURCES}			\
				plat/common/plat_gicv3.c		\
				${PLAT_PATH}/common/k3_gicv3.c		\

K3_PSCI_SOURCES		+=	\
				plat/common/plat_psci_common.c		\
				${PLAT_PATH}/common/k3_psci.c		\

K3_SEC_PROXY_SOURCES	+=	\
				${PLAT_PATH}/common/drivers/sec_proxy/sec_proxy.c \

K3_TI_SCI_SOURCES	+=	\
				${PLAT_PATH}/common/drivers/ti_sci/ti_sci.c \

PLAT_BL_COMMON_SOURCES	+=	\
				lib/cpus/aarch64/cortex_a53.S		\
				lib/cpus/aarch64/cortex_a72.S		\
				${XLAT_TABLES_LIB_SRCS}			\
				${K3_CONSOLE_SOURCES}			\

BL31_SOURCES		+=	\
				${PLAT_PATH}/common/k3_bl31_setup.c	\
				${PLAT_PATH}/common/k3_helpers.S	\
				${PLAT_PATH}/common/k3_topology.c	\
				${K3_GIC_SOURCES}			\
				${K3_PSCI_SOURCES}			\
				${K3_SEC_PROXY_SOURCES}			\
				${K3_TI_SCI_SOURCES}			\
