/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_CAPTURE_COMPOSITE_H
#define SLIM_CAPTURE_COMPOSITE_H

#import <CoreGraphics/CoreGraphics.h>

#import "overlay.h"

/*
 * Crop a CG-global selection out of the per-screen frozen captures and
 * composite the pieces at the highest native scale. Returns a +1 image;
 * the caller owns it.
 */
CGImageRef SlimCopyCompositeFromCaptures(NSArray<SlimScreenCapture *> *captures,
                                         CGRect selection);

#endif /* SLIM_CAPTURE_COMPOSITE_H */
