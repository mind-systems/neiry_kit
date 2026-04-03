// Copyright. 2019 - 2024 PSBD. All rights reserved.

#pragma once

#include "Classification.hpp"

#include <Cardio.hpp>

#include <functional>

namespace capsule::client {
class ClassificationCardioPrivate;
class Device;

class ClassificationCardio final : public Classification {
  public:
    explicit ClassificationCardio(Device& owner) noexcept;

    void SetOnIndexesUpdateEvent(std::function<void(ClassificationCardio&, const cardio::CardioData&)>&& callback);
    void SetOnMetricsUpdateEvent(std::function<void(ClassificationCardio&, const cardio::CardioMetrics&)>&& callback);
    void SetOnCalibratedEvent(std::function<void(ClassificationCardio&)>&& callback);
    void SetOnPPGDataEvent(std::function<void(ClassificationCardio&, cardio::PPGTimedData&&)>&& callback);
#ifdef CC_CHIMERA
    void SetOnDrawDataUpdateEvent(std::function<void(ClassificationCardio&, const cardio::DrawData&)>&& callback);
#endif

  private:
    ClassificationCardioPrivate* getImpl();
    const ClassificationCardioPrivate* getImpl() const;
};

} // namespace capsule::client
