################################################################################
# rx1950 base package
################################################################################

RX1950_BASE_VERSION = 1.0
RX1950_BASE_SITE = $(BR2_EXTERNAL_RX1950_PATH)/package/rx1950-base/src
RX1950_BASE_SITE_METHOD = local

$(eval $(generic-package))
