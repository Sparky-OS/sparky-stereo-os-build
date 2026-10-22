// SPDX-License-Identifier: GPL-2.0
/* Trivial module the bench signs (or not) to test the kernel's module signature policy. */
#include <linux/module.h>
#include <linux/init.h>

static int __init benchmod_init(void)
{
	pr_info("benchmod: loaded\n");
	return 0;
}

static void __exit benchmod_exit(void)
{
	pr_info("benchmod: unloaded\n");
}

module_init(benchmod_init);
module_exit(benchmod_exit);
MODULE_DESCRIPTION("hibernate-bench test module");
MODULE_LICENSE("GPL");
