/* event-config_android.h
 *
 * Android (bionic) differs from glibc for a handful of feature macros.
 * Start from the Linux config and override the bionic-specific ones.
 *
 * See the maintainer notes in //modules/libevent/README.md
 * for hints on how to change this file.
 *
 * Do not rely on macros in this file existing in later versions.
 */
#ifndef EVENT2_CONFIG_ANDROID_H_INCLUDED_
#define EVENT2_CONFIG_ANDROID_H_INCLUDED_

#include "event2-config_linux.h"

/* bionic has provided arc4random() and arc4random_buf() since API 21.
 * The Linux config gates these on EVENT__GLIBC_PREREQ, which is always
 * false on bionic, so define them here. Without this, libevent compiles
 * its own static arc4random_buf() and conflicts with the NDK sysroot
 * declaration in <stdlib.h>. */
#ifndef EVENT__HAVE_ARC4RANDOM
#define EVENT__HAVE_ARC4RANDOM 1
#endif

#ifndef EVENT__HAVE_ARC4RANDOM_BUF
#define EVENT__HAVE_ARC4RANDOM_BUF 1
#endif

#endif  // EVENT2_CONFIG_ANDROID_H_INCLUDED_
