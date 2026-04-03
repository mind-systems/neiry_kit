// Copyright. 2019 - 2024 PSBD. All rights reserved.

#pragma once

#include "CDefinesPrivate.h"

#include <Core/NFB.hpp>

namespace capsule::client {
class Device;
class NFBCalibratorPrivate;
class ClassificationNFB;
class ClassificationProductivity;
class ClassificationEmotions;
class ClassificationNFBPrivate;
class ClassificationProductivityPrivate;
class ClassificationEmotionsPrivate;

/**
 * \brief Calibration for Individual NFB and NFB baseline
 */
class CL_DLL NFBCalibrator final {
    friend NFBCalibratorPrivate;
    friend ClassificationNFB;
    friend ClassificationProductivity;
    friend ClassificationEmotions;
    friend ClassificationNFBPrivate;
    friend ClassificationProductivityPrivate;
    friend ClassificationEmotionsPrivate;

  public:
    enum class Stage : uint8_t {
        Stage1,
        Stage2,
        Stage3,
        Stage4
    };

    explicit NFBCalibrator(Device& owner);

    void CalibrateIndividualNFB(const nfb::IndividualNFBStageInfo& info);
    void CalibrateIndividualNFB(Stage stage);
    void CalibrateIndividualNFBQuick();
    void ImportIndividualNFBData(const nfb::IndividualNFBData& data);

    void SetOnIndividualNFBStageFinishedEvent(std::function<void(NFBCalibrator&)>&& callback);
    void SetOnIndividualNFBCalibratedEvent(std::function<void(NFBCalibrator&, const nfb::IndividualNFBData&)>&& callback);

    bool IsCalibrated() const;
    nfb::IndividualNFBData GetIndividualNFB() const;

  private:
    void CheckValid() const;

    NFBCalibratorPrivate* m_impl;
};

} // namespace capsule::client
