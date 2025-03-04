/*
 * Copyright (c) 2021-2022, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <assert.h>
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <string.h>

#include <arch_helpers.h>
#include <arch_features.h>
#include <bl31/bl31.h>
#include <common/debug.h>
#include <common/runtime_svc.h>
#include <context.h>
#include <lib/el3_runtime/context_mgmt.h>
#include <lib/el3_runtime/pubsub.h>
#include <lib/gpt_rme/gpt_rme.h>

#include <lib/spinlock.h>
#include <lib/utils.h>
#include <lib/xlat_tables/xlat_tables_v2.h>
#include <plat/common/common_def.h>
#include <plat/common/platform.h>
#include <platform_def.h>
#include <services/rmmd_svc.h>
#include <smccc_helpers.h>
#include <lib/extensions/sve.h>
#include "rmmd_initial_context.h"
#include "rmmd_private.h"

/*******************************************************************************
 * RMM context information.
 ******************************************************************************/
rmmd_rmm_context_t rmm_context[PLATFORM_CORE_COUNT];

/*******************************************************************************
 * RMM entry point information. Discovered on the primary core and reused
 * on secondary cores.
 ******************************************************************************/
static entry_point_info_t *rmm_ep_info;

/*******************************************************************************
 * Static function declaration.
 ******************************************************************************/
static int32_t rmm_init(void);

/*******************************************************************************
 * This function takes an RMM context pointer and performs a synchronous entry
 * into it.
 ******************************************************************************/
uint64_t rmmd_rmm_sync_entry(rmmd_rmm_context_t *rmm_ctx)
{
	uint64_t rc;

	assert(rmm_ctx != NULL);

	cm_set_context(&(rmm_ctx->cpu_ctx), REALM);

	/* Save the current el1/el2 context before loading realm context. */
	cm_el1_sysregs_context_save(NON_SECURE);
	cm_el2_sysregs_context_save(NON_SECURE);

	/* Restore the realm context assigned above */
	cm_el1_sysregs_context_restore(REALM);
	cm_el2_sysregs_context_restore(REALM);
	cm_set_next_eret_context(REALM);

	/* Enter RMM */
	rc = rmmd_rmm_enter(&rmm_ctx->c_rt_ctx);

	/* Save realm context */
	cm_el1_sysregs_context_save(REALM);
	cm_el2_sysregs_context_save(REALM);

	/* Restore the el1/el2 context again. */
	cm_el1_sysregs_context_restore(NON_SECURE);
	cm_el2_sysregs_context_restore(NON_SECURE);

	return rc;
}

/*******************************************************************************
 * This function returns to the place where rmmd_rmm_sync_entry() was
 * called originally.
 ******************************************************************************/
__dead2 void rmmd_rmm_sync_exit(uint64_t rc)
{
	rmmd_rmm_context_t *ctx = &rmm_context[plat_my_core_pos()];

	/* Get context of the RMM in use by this CPU. */
	assert(cm_get_context(REALM) == &(ctx->cpu_ctx));

	/*
	 * The RMMD must have initiated the original request through a
	 * synchronous entry into RMM. Jump back to the original C runtime
	 * context with the value of rc in x0;
	 */
	rmmd_rmm_exit(ctx->c_rt_ctx, rc);

	panic();
}

static void rmm_el2_context_init(el2_sysregs_t *regs)
{
	regs->ctx_regs[CTX_SPSR_EL2 >> 3] = REALM_SPSR_EL2;
	regs->ctx_regs[CTX_SCTLR_EL2 >> 3] = SCTLR_EL2_RES1;
}

/*******************************************************************************
 * Enable architecture extensions on first entry to Realm world.
 ******************************************************************************/
static void manage_extensions_realm(cpu_context_t *ctx)
{
#if ENABLE_SVE_FOR_NS
	/*
	 * Enable SVE and FPU in realm context when it is enabled for NS.
	 * Realm manager must ensure that the SVE and FPU register
	 * contexts are properly managed.
	 */
	sve_enable(ctx);
#else
	/*
	 * Disable SVE and FPU in realm context when it is disabled for NS.
	 */
	sve_disable(ctx);
#endif /* ENABLE_SVE_FOR_NS */
}

/*******************************************************************************
 * Jump to the RMM for the first time.
 ******************************************************************************/
static int32_t rmm_init(void)
{

	uint64_t rc;

	rmmd_rmm_context_t *ctx = &rmm_context[plat_my_core_pos()];

	INFO("RMM init start.\n");
	ctx->state = RMM_STATE_RESET;

	/* Enable architecture extensions */
	manage_extensions_realm(&ctx->cpu_ctx);

	/* Initialize RMM EL2 context. */
	rmm_el2_context_init(&ctx->cpu_ctx.el2_sysregs_ctx);

	rc = rmmd_rmm_sync_entry(ctx);
	if (rc != 0ULL) {
		ERROR("RMM initialisation failed 0x%" PRIx64 "\n", rc);
		panic();
	}

	ctx->state = RMM_STATE_IDLE;
	INFO("RMM init end.\n");

	return 1;
}

/*******************************************************************************
 * Load and read RMM manifest, setup RMM.
 ******************************************************************************/
int rmmd_setup(void)
{
	uint32_t ep_attr;
	unsigned int linear_id = plat_my_core_pos();
	rmmd_rmm_context_t *rmm_ctx = &rmm_context[linear_id];

	/* Make sure RME is supported. */
	assert(get_armv9_2_feat_rme_support() != 0U);

	rmm_ep_info = bl31_plat_get_next_image_ep_info(REALM);
	if (rmm_ep_info == NULL) {
		WARN("No RMM image provided by BL2 boot loader, Booting "
		     "device without RMM initialization. SMCs destined for "
		     "RMM will return SMC_UNK\n");
		return -ENOENT;
	}

	/* Under no circumstances will this parameter be 0 */
	assert(rmm_ep_info->pc == RMM_BASE);

	/* Initialise an entrypoint to set up the CPU context */
	ep_attr = EP_REALM;
	if ((read_sctlr_el3() & SCTLR_EE_BIT) != 0U) {
		ep_attr |= EP_EE_BIG;
	}

	SET_PARAM_HEAD(rmm_ep_info, PARAM_EP, VERSION_1, ep_attr);
	rmm_ep_info->spsr = SPSR_64(MODE_EL2,
					MODE_SP_ELX,
					DISABLE_ALL_EXCEPTIONS);

	/* Initialise RMM context with this entry point information */
	cm_setup_context(&rmm_ctx->cpu_ctx, rmm_ep_info);

	INFO("RMM setup done.\n");

	/* Register init function for deferred init.  */
	bl31_register_rmm_init(&rmm_init);

	return 0;
}

/*******************************************************************************
 * Forward SMC to the other security state
 ******************************************************************************/
static uint64_t	rmmd_smc_forward(uint32_t src_sec_state,
					uint32_t dst_sec_state, uint64_t x0,
					uint64_t x1, uint64_t x2, uint64_t x3,
					uint64_t x4, void *handle)
{
	/* Save incoming security state */
	cm_el1_sysregs_context_save(src_sec_state);
	cm_el2_sysregs_context_save(src_sec_state);

	/* Restore outgoing security state */
	cm_el1_sysregs_context_restore(dst_sec_state);
	cm_el2_sysregs_context_restore(dst_sec_state);
	cm_set_next_eret_context(dst_sec_state);

	/*
	 * As per SMCCCv1.1, we need to preserve x4 to x7 unless
	 * being used as return args. Hence we differentiate the
	 * onward and backward path. Support upto 8 args in the
	 * onward path and 4 args in return path.
	 */
	if (src_sec_state == NON_SECURE) {
		SMC_RET8(cm_get_context(dst_sec_state), x0, x1, x2, x3, x4,
				SMC_GET_GP(handle, CTX_GPREG_X5),
				SMC_GET_GP(handle, CTX_GPREG_X6),
				SMC_GET_GP(handle, CTX_GPREG_X7));
	} else {
		SMC_RET4(cm_get_context(dst_sec_state), x0, x1, x2, x3);
	}
}

/*******************************************************************************
 * This function handles all SMCs in the range reserved for RMI. Each call is
 * either forwarded to the other security state or handled by the RMM dispatcher
 ******************************************************************************/
uint64_t rmmd_rmi_handler(uint32_t smc_fid, uint64_t x1, uint64_t x2,
				uint64_t x3, uint64_t x4, void *cookie,
				void *handle, uint64_t flags)
{
	rmmd_rmm_context_t *ctx = &rmm_context[plat_my_core_pos()];
	uint32_t src_sec_state;

	/* Determine which security state this SMC originated from */
	src_sec_state = caller_sec_state(flags);

	/* RMI must not be invoked by the Secure world */
	if (src_sec_state == SMC_FROM_SECURE) {
		WARN("RMMD: RMI invoked by secure world.\n");
		SMC_RET1(handle, SMC_UNK);
	}

	/*
	 * Forward an RMI call from the Normal world to the Realm world as it
	 * is.
	 */
	if (src_sec_state == SMC_FROM_NON_SECURE) {
		VERBOSE("RMMD: RMI call from non-secure world.\n");
		return rmmd_smc_forward(NON_SECURE, REALM, smc_fid,
					x1, x2, x3, x4, handle);
	}

	if (src_sec_state != SMC_FROM_REALM) {
		SMC_RET1(handle, SMC_UNK);
	}

	switch (smc_fid) {
	case RMMD_RMI_REQ_COMPLETE:
		if (ctx->state == RMM_STATE_RESET) {
			VERBOSE("RMMD: running rmmd_rmm_sync_exit\n");
			rmmd_rmm_sync_exit(x1);
		}

		return rmmd_smc_forward(REALM, NON_SECURE, x1,
					x2, x3, x4, 0, handle);

	default:
		WARN("RMMD: Unsupported RMM call 0x%08x\n", smc_fid);
		SMC_RET1(handle, SMC_UNK);
	}
}

/*******************************************************************************
 * This cpu has been turned on. Enter RMM to initialise R-EL2.  Entry into RMM
 * is done after initialising minimal architectural state that guarantees safe
 * execution.
 ******************************************************************************/
static void *rmmd_cpu_on_finish_handler(const void *arg)
{
	int32_t rc;
	uint32_t linear_id = plat_my_core_pos();
	rmmd_rmm_context_t *ctx = &rmm_context[linear_id];

	ctx->state = RMM_STATE_RESET;

	/* Initialise RMM context with this entry point information */
	cm_setup_context(&ctx->cpu_ctx, rmm_ep_info);

	/* Enable architecture extensions */
	manage_extensions_realm(&ctx->cpu_ctx);

	/* Initialize RMM EL2 context. */
	rmm_el2_context_init(&ctx->cpu_ctx.el2_sysregs_ctx);

	rc = rmmd_rmm_sync_entry(ctx);
	if (rc != 0) {
		ERROR("RMM initialisation failed (%d) on CPU%d\n", rc,
		      linear_id);
		panic();
	}

	ctx->state = RMM_STATE_IDLE;
	return NULL;
}

/* Subscribe to PSCI CPU on to initialize RMM on secondary */
SUBSCRIBE_TO_EVENT(psci_cpu_on_finish, rmmd_cpu_on_finish_handler);

/* Convert GPT lib error to RMMD GTS error */
static int gpt_to_gts_error(int error, uint32_t smc_fid, uint64_t address)
{
	int ret;

	if (error == 0) {
		return RMMD_OK;
	}

	if (error == -EINVAL) {
		ret = RMMD_ERR_BAD_ADDR;
	} else {
		/* This is the only other error code we expect */
		assert(error == -EPERM);
		ret = RMMD_ERR_BAD_PAS;
	}

	ERROR("RMMD: PAS Transition failed. GPT ret = %d, PA: 0x%"PRIx64 ", FID = 0x%x\n",
				error, address, smc_fid);
	return ret;
}

/*******************************************************************************
 * This function handles RMM-EL3 interface SMCs
 ******************************************************************************/
uint64_t rmmd_rmm_el3_handler(uint32_t smc_fid, uint64_t x1, uint64_t x2,
				uint64_t x3, uint64_t x4, void *cookie,
				void *handle, uint64_t flags)
{
	uint32_t src_sec_state;
	int ret;

	/* Determine which security state this SMC originated from */
	src_sec_state = caller_sec_state(flags);

	if (src_sec_state != SMC_FROM_REALM) {
		WARN("RMMD: RMM-EL3 call originated from secure or normal world\n");
		SMC_RET1(handle, SMC_UNK);
	}

	switch (smc_fid) {
	case RMMD_GTSI_DELEGATE:
		ret = gpt_delegate_pas(x1, PAGE_SIZE_4KB, SMC_FROM_REALM);
		SMC_RET1(handle, gpt_to_gts_error(ret, smc_fid, x1));
	case RMMD_GTSI_UNDELEGATE:
		ret = gpt_undelegate_pas(x1, PAGE_SIZE_4KB, SMC_FROM_REALM);
		SMC_RET1(handle, gpt_to_gts_error(ret, smc_fid, x1));
	case RMMD_ATTEST_GET_PLAT_TOKEN:
		ret = rmmd_attest_get_platform_token(x1, &x2, x3);
		SMC_RET2(handle, ret, x2);
	case RMMD_ATTEST_GET_REALM_KEY:
		ret = rmmd_attest_get_signing_key(x1, &x2, x3);
		SMC_RET2(handle, ret, x2);
	default:
		WARN("RMMD: Unsupported RMM-EL3 call 0x%08x\n", smc_fid);
		SMC_RET1(handle, SMC_UNK);
	}
}
