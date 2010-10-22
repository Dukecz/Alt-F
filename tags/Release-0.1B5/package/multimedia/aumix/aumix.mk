#############################################################
#
# aumix
#
#############################################################

AUMIX_VERSION=2.8
AUMIX_SOURCE=aumix-$(AUMIX_VERSION).tar.bz2
AUMIX_SITE=http://jpj.net/~trevor/aumix
AUMIX_DIR=$(BUILD_DIR)/aumix-$(AUMIX_VERSION)
AUMIX_CAT:=$(BZCAT)

$(DL_DIR)/$(AUMIX_SOURCE):
	$(call DOWNLOAD,$(AUMIX_SITE),$(AUMIX_SOURCE))

$(AUMIX_DIR)/.unpacked: $(DL_DIR)/$(AUMIX_SOURCE)
	$(AUMIX_CAT) $(DL_DIR)/$(AUMIX_SOURCE) | tar -C $(BUILD_DIR) $(TAR_OPTIONS) -
	touch $@

$(AUMIX_DIR)/.configured: $(AUMIX_DIR)/.unpacked
	(cd $(AUMIX_DIR); rm -rf config.cache; \
		$(TARGET_CONFIGURE_OPTS) \
		$(TARGET_CONFIGURE_ARGS) \
		./configure \
		--target=$(GNU_TARGET_NAME) \
		--host=$(GNU_TARGET_NAME) \
		--build=$(GNU_HOST_NAME) \
		--prefix=/usr \
		--sysconfdir=/etc \
		--libdir=$(STAGING_DIR)/lib \
		--includedir=$(STAGING_DIR)/usr/include \
		--without-gtk \
		--without-gtk1 \
		--without-alsa \
		--without-gpm \
		--without-sysmouse \
		$(DISABLE_NLS) \
	)
	touch $@

$(AUMIX_DIR)/src/aumix: $(AUMIX_DIR)/.configured
	$(MAKE) CC=$(TARGET_CC) -C $(AUMIX_DIR)

$(TARGET_DIR)/usr/bin/aumix: $(AUMIX_DIR)/src/aumix
	$(MAKE) -C $(AUMIX_DIR) DESTDIR=$(TARGET_DIR) install

aumix: uclibc ncurses $(TARGET_DIR)/usr/bin/aumix

aumix-source: $(DL_DIR)/$(AUMIX_SOURCE)

aumix-clean:
	-$(MAKE) -C $(AUMIX_DIR) clean

aumix-dirclean:
	rm -rf $(AUMIX_DIR)
#############################################################
#
# Toplevel Makefile options
#
#############################################################
ifeq ($(BR2_PACKAGE_AUMIX),y)
TARGETS+=aumix
endif
