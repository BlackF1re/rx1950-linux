// SPDX-License-Identifier: GPL-2.0
/*
 * HP iPAQ rx1950 glue for the TI TNETW1100B / ACX100 slave-memory WLAN.
 *
 * The ACX driver itself is intentionally kept out of the boot-critical
 * RX1950 platform-device array. Loading this module configures only the WLAN
 * external bus and registers an acx-mem platform device, so a failed WLAN
 * probe cannot roll back the SD controller or prevent the root filesystem
 * from mounting.
 *
 * The GPIO sequence follows the historical RX1950 ACX platform driver:
 * GPH10/CLKOUT1, GPA15/nGCS4, GPC8/GPC9 high, GPA14 reset and GPA11 power.
 * Mainline RX1950 also exposes GPA11 as the visible Blue LED and gives it the
 * default trigger "rx1950-acx-mem". We therefore drive the shared GPA11 line
 * through the LED trigger API instead of stealing the GPIO from leds-gpio.
 */

#include <linux/delay.h>
#include <linux/gpio.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/ioport.h>
#include <linux/leds.h>
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
#define RX1950_WLAN_AUX1          S3C2410_GPC(8)
#define RX1950_WLAN_AUX2          S3C2410_GPC(9)

static bool gpa11_power = true;
module_param(gpa11_power, bool, 0444);
MODULE_PARM_DESC(gpa11_power,
	"Drive the historical GPA11 WLAN power/Blue line (default: true). "
	"Set to false only to test whether the radio can run independently of Blue");

static struct led_trigger *rx1950_wlan_power_trigger;

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
	if (gpa11_power)
		led_trigger_event(rx1950_wlan_power_trigger, LED_OFF);

	gpio_set_value(RX1950_WLAN_RESET, 0);

	/* Return the historical external WLAN bus pins to an inactive state. */
	s3c_gpio_cfgpin(RX1950_WLAN_NGCS4, S3C2410_GPIO_OUTPUT);
	gpio_set_value(RX1950_WLAN_NGCS4, 1);
	gpio_set_value(RX1950_WLAN_AUX1, 0);
	gpio_set_value(RX1950_WLAN_AUX2, 0);
	s3c_gpio_cfgpin(RX1950_WLAN_CLKOUT1, S3C2410_GPIO_OUTPUT);
	gpio_set_value(RX1950_WLAN_CLKOUT1, 0);
}

static void rx1950_wlan_gpio_free(void)
{
	gpio_free(RX1950_WLAN_AUX2);
	gpio_free(RX1950_WLAN_AUX1);
	gpio_free(RX1950_WLAN_RESET);
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

	ret = gpio_request(RX1950_WLAN_AUX1, "rx1950-wlan-aux1");
	if (ret)
		goto err_reset;

	ret = gpio_direction_output(RX1950_WLAN_AUX1, 1);
	if (ret)
		goto err_aux1;

	ret = gpio_request(RX1950_WLAN_AUX2, "rx1950-wlan-aux2");
	if (ret)
		goto err_aux1;

	ret = gpio_direction_output(RX1950_WLAN_AUX2, 1);
	if (ret)
		goto err_aux2;

	/*
	 * Reproduce the external-memory wiring used by the original RX1950 port:
	 *   GPH10 -> CLKOUT1, GPA15 -> nGCS4, GPG8 -> EINT16.
	 * GPC8/GPC9 are also asserted high by that known RX1950 WLAN sequence.
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

	/* Historical RX1950 code held reset low for 200 ms before release. */
	msleep(200);
	gpio_set_value(RX1950_WLAN_RESET, 1);

	if (gpa11_power)
		led_trigger_event(rx1950_wlan_power_trigger, LED_FULL);

	msleep(50);
	pr_info("rx1950-acx: WLAN bus ready, mmio=%#x irq=%d gpa11_power=%d\n",
		RX1950_WLAN_BASE, irq, gpa11_power);
	return 0;

err_bus:
	rx1950_wlan_bus_stop();
err_aux2:
	gpio_free(RX1950_WLAN_AUX2);
err_aux1:
	gpio_free(RX1950_WLAN_AUX1);
err_reset:
	gpio_free(RX1950_WLAN_RESET);
	return ret;
}

static int __init rx1950_acx_init(void)
{
	int ret;

	if (gpa11_power) {
		led_trigger_register_simple("rx1950-acx-mem",
			&rx1950_wlan_power_trigger);
		if (!rx1950_wlan_power_trigger) {
			pr_err("rx1950-acx: cannot register GPA11/Blue power trigger\n");
			return -ENODEV;
		}
	}

	ret = rx1950_wlan_bus_start();
	if (ret) {
		pr_err("rx1950-acx: failed to configure WLAN bus: %d\n", ret);
		goto err_trigger;
	}

	ret = platform_device_register(&rx1950_acx_device);
	if (ret) {
		pr_err("rx1950-acx: failed to register acx-mem device: %d\n", ret);
		rx1950_wlan_bus_stop();
		rx1950_wlan_gpio_free();
		goto err_trigger;
	}

	pr_info("rx1950-acx: acx-mem platform device registered\n");
	return 0;

err_trigger:
	if (gpa11_power) {
		led_trigger_unregister_simple(rx1950_wlan_power_trigger);
		rx1950_wlan_power_trigger = NULL;
	}
	return ret;
}

static void __exit rx1950_acx_exit(void)
{
	platform_device_unregister(&rx1950_acx_device);
	rx1950_wlan_bus_stop();
	rx1950_wlan_gpio_free();
	if (gpa11_power) {
		led_trigger_unregister_simple(rx1950_wlan_power_trigger);
		rx1950_wlan_power_trigger = NULL;
	}
	pr_info("rx1950-acx: WLAN bus disabled\n");
}

module_init(rx1950_acx_init);
module_exit(rx1950_acx_exit);

MODULE_AUTHOR("BlackF1re");
MODULE_DESCRIPTION("HP iPAQ rx1950 ACX100 slave-memory platform glue");
MODULE_LICENSE("GPL");
MODULE_ALIAS("platform:rx1950-acx");
