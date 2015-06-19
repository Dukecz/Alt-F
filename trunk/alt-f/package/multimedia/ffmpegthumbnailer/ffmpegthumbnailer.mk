#############################################################
#
# ffmpegthumbnailer
#
#############################################################

# requires cmake
#https://github.com/dirkvdb/ffmpegthumbnailer/releases/download/2.0.10/ffmpegthumbnailer-2.0.10.tar.bz2
# FFMPEGTHUMBNAILER_VERSION = 2.0.10
# FFMPEGTHUMBNAILER_SOURCE = ffmpegthumbnailer-$(FFMPEGTHUMBNAILER_VERSION).tar.bz2
# FFMPEGTHUMBNAILER_SITE = https://github.com/dirkvdb/ffmpegthumbnailer/releases/download/$(FFMPEGTHUMBNAILER_VERSION)

FFMPEGTHUMBNAILER_VERSION = 2.0.8
FFMPEGTHUMBNAILER_SOURCE = ffmpegthumbnailer-$(FFMPEGTHUMBNAILER_VERSION).tar.gz
FFMPEGTHUMBNAILER_SITE = http://ffmpegthumbnailer.googlecode.com/files

FFMPEGTHUMBNAILER_AUTORECONF = NO
FFMPEGTHUMBNAILER_LIBTOOL_PATCH = NO

FFMPEGTHUMBNAILER_INSTALL_STAGING = YES
FFMPEGTHUMBNAILER_INSTALL_TARGET = YES

FFMPEGTHUMBNAILER_DEPENDENCIES = uclibc ffmpeg jpeg libpng

FFMPEGTHUMBNAILER_CONF_OPT = --disable-static --enable-png --enable-jpeg
FFMPEGTHUMBNAILER_CONF_ENV = PKG_CONFIG_PATH=$(STAGING_DIR)/usr/lib/pkgconfig/

$(eval $(call AUTOTARGETS,package/multimedia,ffmpegthumbnailer))
