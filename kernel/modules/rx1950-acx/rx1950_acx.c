// SPDX-License-Identifier: GPL-2.0
/*
 * HP iPAQ rx1950 glue for the TI TNETW1100B / ACX100 slave-memory WLAN.
 *
 * The ACX driver itself is intentionally kept out of the boot-critical
 * RX1950 platform-device array.  Loading this module configures only the WLAN
 * external-bus pins and registers an acx-mem platform device, so a failed WLAN
 * probe cannot roll back the SD controller or prevent the root filesystem from
 * mounting.
 *
 * Historical RX1950 code labelled GPA11 as WLAN power, while the upstream
 * RX1950 board file also exposes the same GPIO as the visible Blue LED.  To
 * preserve independent Blue LED control, GPA11 is NOT touched by default.
 * The gpa11_power module parameter exists only as an explicit hardware
 * diagnostic fallback; enabling it necessarily couples radio power and Blue.
 */

#include <linux/delay.h>
#include <linux/gpio.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/ioport.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/platform_device.h>

#include "gpio-cfg.h"
#include "gpio-samsung.h"
#include "regs-gpio.h"

#define RX1950_WLAN_BASE          0x20000000
#define RX1950_WLAN_RESET         S3C2410_GPA(14)
#define RX1950_WLAN_NGCS4         S3C2410_GPA(15)
#define RX1950_WLAN_CLKOUT1       S3C2410_GPH(10)
#define RX1950_WLAN_IRQ_GPIO      S3C2410_GPG(8)
#define RX1950_WLAN_GPA11         S3C2410_GPA(11)

static bool gpa11_power;
module_param(gpa11_power, bool, 0444);
MODULE_PARM_DESC(gpa11_power,
	"Drive GPA11 high while WLAN is active. Diagnostic fallback only: "
	"GPA11 is also the physical Blue LED on RX1950");

static struct resource rx1950_acx_resources[] = {
	{
		.start = RX1950_WLAN_BASE,
		.end = RX1950_WLAN_BASE + 0x20,
		.flags = IORESOURCE_MEM,
	},
	{
		.flags = IORESOURCE_IRQ,
	},
};

static void rx1950_acx_release(struct device *dev)
{
}

static struct platform_device rx1950_acx_device = {
	.name = "acx-mem",
	.id = -1,
	.dev = {
		.release = rx1950_acx_release,
	},
	.num_resources = ARRAY_SIZE(rx1950_acx_resources),
	.resource = rx1950_acx_resources,
};

static void rx1950_wlan_bus_stop(void)
{
	gpio_set_value(RX1950_WLAN_RESET, 0);

	if (gpa11_power)
		gpio_set_value(RX1950_WLAN_GPA11, 0);

	/* Disconnect the external WLAN bus and its clock when the module leaves. */
	s3c_gpio_cfgpin(RX1950_WLAN_NGCS4, S3C2410_GPIO_OUTPUT);
	gpio_set_value(RX1950_WLAN_NGCS4, 1);
	s3c_gpio_cfgpin(RX1950_WLAN_CLKOUT1, S3C2410_GPIO_OUTPUT);
	gpio_set_value(RX1950_WLAN_CLKOUT1, 0);
}

static int rx1950_wlan_bus_start(void)
{
	int irq;
	int ret;

	ret = gpio_request(RX1950_WLAN_RESET, "rx1950-wlan-reset");
	if (ret)
		return ret;

	ret = gpio_direction_output(RX1950_WLAN_RESET, 0);
	if (ret)
		goto err_reset;

	/*
	 * Reproduce the external-memory wiring used by the original RX1950 port:
	 *   GPH10 -> CLKOUT1, GPA15 -> nGCS4, GPG8 -> EINT16.
	 * GPC8/GPC9 from the old experimental glue are deliberately untouched;
	 * they overlap the active LCD data bus in the upstream RX1950 board file.
	 */
	s3c_gpio_cfgpin(RX1950_WLAN_CLKOUT1, S3C2410_GPH10_CLKOUT1);
	s3c_gpio_setpull(RX1950_WLAN_CLKOUT1, S3C_GPIO_PULL_NONE);
	s3c_gpio_cfgpin(RX1950_WLAN_NGCS4, S3C2410_GPA15_nGCS4);
	s3c_gpio_cfgpin(RX1950_WLAN_IRQ_GPIO, S3C2410_GPIO_IRQ);
	s3c_gpio_setpull(RX1950_WLAN_IRQ_GPIO, S3C_GPIO_PULL_NONE);

	irq = gpio_to_irq(RX1950_WLAN_IRQ_GPIO);
	if (irq < 0) {
		ret = irq;
		goto err_bus;
	}
	rx1950_acx_resources[1].start = irq;
	rx1950_acx_resources[1].end = irq;

	if (gpa11_power) {
		/*
		 * Do not request GPA11: leds-gpio already owns it as Blue.  This is
		 * intentionally an opt-in compatibility diagnostic for the historical
		 * board glue and cannot provide independent Blue control.
		 */
		pr_warn("rx1950-acx: gpa11_power=1 couples WLAN power to the Blue LED\n");
		gpio_set_value(RX1950_WLAN_GPA11, 1);
	}

	/* The historical driver held reset low for 200 ms before releasing it. */
	msleep(200);
	gpio_set_value(RX1950_WLAN_RESET, 1);
	msleep(50);

	pr_info("rx1950-acx: WLAN bus ready, mmio=%#x irq=%d gpa11_power=%d\n",
		RX1950_WLAN_BASE, irq, gpa11_power);
	return 0;

err_bus:
	rx1950_wlan_bus_stop();
err_reset:
	gpio_free(RX1950_WLAN_RESET);
	return ret;
}

static int __init rx1950_acx_init(void)
{
	int ret;

	ret = rx1950_wlan_bus_start();
	if (ret) {
		pr_err("rx1950-acx: failed to configure WLAN bus: %d\n", ret);
		return ret;
	}

	ret = platform_device_register(&rx1950_acx_device);
	if (ret) {
		pr_err("rx1950-acx: failed to register acx-mem device: %d\n", ret);
		rx1950_wlan_bus_stop();
		gpio_free(RX1950_WLAN_RESET);
		return ret;
	}

	pr_info("rx1950-acx: acx-mem platform device registered\n");
	return 0;
}

static void __exit rx1950_acx_exit(void)
{
	platform_device_unregister(&rx1950_acx_device);
	rx1950_wlan_bus_stop();
	gpio_free(RX1950_WLAN_RESET);
	pr_info("rx1950-acx: WLAN bus disabled\n");
}

module_init(rx1950_acx_init);
module_exit(rx1950_acx_exit);

MODULE_AUTHOR("BlackF1re");
MODULE_DESCRIPTION("HP iPAQ rx1950 ACX100 slave-memory platform glue");
MODULE_LICENSE("GPL");
MODULE_ALIAS("platform:rx1950-acx");
