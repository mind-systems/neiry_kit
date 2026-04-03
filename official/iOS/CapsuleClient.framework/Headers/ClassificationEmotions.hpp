// Copyright. 2019 - 2024 PSBD. All rights reserved.

#pragma once

#include "CDefinesPrivate.h"
#include "Classification.hpp"

#include <Core/Common.hpp>
#include <Core/Delegate.hpp>

namespace capsule::client {
class ClassificationEmotionsPrivate;
class Device;

/**
 * \brief Wrapper of \ref ClassificationNFB class
 *
 * Use it for metrics described in \ref Metrics enumeration.
 */
class CL_DLL ClassificationEmotions : public Classification {
    friend ClassificationEmotionsPrivate;

  public:
    enum class CallResult : uint8_t {
        Success,          /**< Call has finished successfully. */
        FailedToSendData, /**< Failed to send data, session might not be active. */
        ClassifierIsBusy
    };

    explicit ClassificationEmotions(Device& owner);

    void SetOnEmotionalStatesUpdateEvent(std::function<void(ClassificationEmotions&, const emotions::EmotionalStates&)>&& callback);
    void SetOnErrorEvent(std::function<void(ClassificationEmotions&, const std::string&)>&& callback);
    // void SetOnStatusChangedEvent(std::function<void(ClassificationEmotions&, core::ClassifierStatus)>&& callback);

  private:
    ClassificationEmotionsPrivate* getImpl();
    const ClassificationEmotionsPrivate* getImpl() const;
};

} // namespace capsule::client
