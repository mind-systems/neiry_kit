// Copyright. 2019 - 2024 PSBD. All rights reserved.

#pragma once

#include "CDefinesPrivate.h"
#include "Classification.hpp"

#include <Core/Common.hpp>
#include <Core/Delegate.hpp>

namespace capsule::client {
class ClassificationNFBPrivate;
class Device;

/**
 * \brief Interface to NFB classification process.
 *
 * Before calling any of the functions make sure that:
 * * A valid \ref Session created with Client::CreateSession is passed to
 * the constructor.
 * * \ref Session is active.
 *
 * Model might need to be trained before it is able to calculate user state.
 * ClassificationNFB::IsModelTrained will return \c false if it needs to be
 * trained.
 *
 * In order to train model you should mark each state at least once,
 * with duration no less than a time window
 */
class CL_DLL ClassificationNFB final : public Classification {
    friend ClassificationNFBPrivate;

  public:
    /**
     * \brief NFB call result.
     */
    enum class CallResult : uint8_t {
        Success,                      /**< Call has finished successfully. */
        ModelIsNotTrained_Deprecated, /**< Model was not trained, must be trained first. */
        ModelIsTrained_Deprecated,    /**< Model is already trained, does not need any training. */
        FailedToSendData              /**< Failed to send data, session might not be active. */
    };

    explicit ClassificationNFB(Device& owner);

    void SetOnUserStateChangedEvent(std::function<void(ClassificationNFB&, const nfb::NFBValue&)>&& callback);
    void SetOnErrorEvent(std::function<void(ClassificationNFB&, const std::string&)>&& callback);

  private:
    ClassificationNFBPrivate* getImpl();
    const ClassificationNFBPrivate* getImpl() const;
};

} // namespace capsule::client
