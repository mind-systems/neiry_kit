// Copyright. 2019 - 2024 PSBD. All rights reserved.

#pragma once

#include "CDefinesPrivate.h"
#include "Classification.hpp"

#include <Core/Common.hpp>
#include <Core/Delegate.hpp>

namespace capsule::client {
class ClassificationProductivityPrivate;
class Device;

/**
 * \brief Interface to Productivity process.
 *
 * Before calling any of the functions make sure that:
 * * A valid \ref Session created with Client::CreateSession is passed to
 * the constructor.
 * * \ref Session is active.
 *
 * Model might need to be trained before it is able to calculate user productivity state.
 * And need to be calibration baselines
 *
 * In order to train model you should:
 * * Mark each state at least once, with duration no less than a time window
 */
class CL_DLL ClassificationProductivity final : public Classification {
    friend ClassificationProductivityPrivate;

  public:
    explicit ClassificationProductivity(Device& owner);

    void SetOnMetricsUpdateEvent(std::function<void(ClassificationProductivity&, const productivity::Metrics&)>&& callback);
    void SetOnIndexesUpdateEvent(std::function<void(ClassificationProductivity&, const productivity::Indexes&)>&& callback);
    void SetOnBaselineUpdateEvent(std::function<void(ClassificationProductivity&, const productivity::Baselines&)>&& callback);
    void SetOnCalibrationProgressUpdateEvent(std::function<void(ClassificationProductivity&, float)>&& callback);
    void SetOnIndividualNFBUpdateEvent(std::function<void(ClassificationProductivity&)>&& callback);

    /**
     * \brief request to measure and send status indexes - GetOnIndexesStateEvent will receive a response within 5 minutes
     *
     *	make sure that the process of initialization and measurement of individual alpha range was successful
     *
     * \returns call result.
     */
    void RequestIndexesState();

    /**
     * \brief it is necessary to calibrate the getting values
     */
    void StartBaselineCalibration();

    /**
     * \brief Reset accumulated fatigue
     */
    void ResetAccumulatedFatigue();

    /**
     * \brief Imports baseline values
     */
    void ImportBaselines(const productivity::Baselines& baseline);

  private:
    ClassificationProductivityPrivate* getImpl();
    const ClassificationProductivityPrivate* getImpl() const;
};

} // namespace capsule::client
