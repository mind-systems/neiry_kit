// Copyright. 2019 - 2024 PSBD. All rights reserved.

#pragma once

#include "Classification.hpp"

#include <MEMS.hpp>

#include <functional>

namespace capsule::client {
class ClassificationMEMSPrivate;
class Device;

class ClassificationMEMS final : public Classification {
  public:
    explicit ClassificationMEMS(Device& device) noexcept;

    void SetOnMEMSDataEvent(std::function<void(ClassificationMEMS&, mems::MEMSTimedData&&)>&& callback);

  private:
    ClassificationMEMSPrivate* getImpl();
    const ClassificationMEMSPrivate* getImpl() const;
};

} // namespace capsule::client
