// Copyright. 2019 - 2024 PSBD. All rights reserved.
#pragma once

#include "CDefinesPrivate.h"
#include "Classification.hpp"

#include <Core/Common.hpp>
#include <Core/Delegate.hpp>

namespace capsule::client {
class ClassificationPhysiologicalStatesPrivate;
class Device;

class CL_DLL ClassificationPhysiologicalStates final : public Classification {
    friend ClassificationPhysiologicalStatesPrivate;

  public:
    explicit ClassificationPhysiologicalStates(Device& owner);

    void SetOnPhysiologicalStatesUpdateEvent(std::function<void(ClassificationPhysiologicalStates&, const physiological_states::PhysiologicalStates&)>&& callback);
    void SetOnCalibratedEvent(std::function<void(ClassificationPhysiologicalStates&, const physiological_states::Baselines&)>&& callback);
    void SetOnCalibrationProgressUpdateEvent(std::function<void(ClassificationPhysiologicalStates&, float)>&& callback);
    void SetOnIndividualNFBUpdateEvent(std::function<void(ClassificationPhysiologicalStates&)>&& callback);

    /**
     * \brief Request calibration
     *
     * Requires EEG and PPG signals turned on. OnCalibrated event is called on completion.
     */
    void StartBaselineCalibration();

    /**
     * \brief Import calibration coefficients
     *
     * \param baselines baselines values
     */
    void ImportBaselines(const physiological_states::Baselines& baselines);

  private:
    ClassificationPhysiologicalStatesPrivate* getImpl();
    const ClassificationPhysiologicalStatesPrivate* getImpl() const;
};

} // namespace capsule::client
