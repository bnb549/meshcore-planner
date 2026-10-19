#include "ITMBridge.h"
#include "itm.h"

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
) {
    if (result == nullptr) {
        return 1017;
    }
    result->lossDb = 0;
    result->errorCode = 1017;
    result->warnings = 0;
    result->propagationMode = 0;
    result->freeSpaceLossDb = 0;
    if (profile == nullptr || profileCount < 4) {
        return result->errorCode;
    }
    const int intervals = static_cast<int>(profile[0]);
    if (intervals < 1 || profileCount < intervals + 3) {
        return result->errorCode;
    }

    IntermediateValues values = {};
    double loss = 0;
    long warnings = 0;
    const int code = ITM_P2P_TLS_Ex(
        txHeightM,
        rxHeightM,
        profile,
        climate,
        refractivity,
        frequencyMHz,
        polarization,
        dielectric,
        conductivity,
        variabilityMode,
        timePercent,
        locationPercent,
        situationPercent,
        &loss,
        &warnings,
        &values
    );
    result->lossDb = loss;
    result->errorCode = code;
    result->warnings = static_cast<int32_t>(warnings);
    result->propagationMode = values.mode;
    result->freeSpaceLossDb = values.A_fs__db;
    return code;
}
