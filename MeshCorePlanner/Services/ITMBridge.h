#ifndef ITM_BRIDGE_H
#define ITM_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Result of one NTIA ITM point-to-point call.
/// errorCode 0 is success. errorCode 1 is success with warnings. Other codes are rejections.
typedef struct ITMPathLoss {
    double lossDb;
    int32_t errorCode;
    int32_t warnings;
    int32_t propagationMode;
    double freeSpaceLossDb;
} ITMPathLoss;

/// `profile` is NTIA PFL order: [pointCount - 1, spacingMeters, elevation0, elevation1, ...].
/// The call is reentrant. It does not retain `profile`.
int32_t itm_point_to_point(
    const double *profile,
    int32_t profileCount,
    double txHeightM,
    double rxHeightM,
    double frequencyMHz,
    int32_t climate,
    int32_t polarization,
    double dielectric,
    double conductivity,
    double refractivity,
    int32_t variabilityMode,
    double timePercent,
    double locationPercent,
    double situationPercent,
    ITMPathLoss *result
);

#ifdef __cplusplus
}
#endif

#endif
