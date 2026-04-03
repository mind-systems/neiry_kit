// Copyright. 2019 - 2024 PSBD. All rights reserved.

#pragma once

#include <memory>

namespace capsule::client {
class Session;
class SessionPrivate;
class ClassificationPrivate;
class DevicePrivate;

/**
 * \brief is the base class for to NFB or productivity classification process.
 */
class Classification {
    friend Session;
    friend SessionPrivate;
    friend ClassificationPrivate;
    friend DevicePrivate;

  public:
    enum class ClassifierType : uint8_t {
        Cardio = 0,
        Emotions = 1,
        NFB = 1 << 1,
        MEMS = 1 << 2,
        Physiological = 1 << 4,
        Productivity = 1 << 5
    };
    bool IsValid() const noexcept;
    Classification(const Classification&) = delete;
    Classification& operator=(const Classification&) = delete;
    Classification(Classification&& rhs) noexcept;
    Classification& operator=(Classification&& rhs) noexcept;

  protected:
    explicit Classification(std::unique_ptr<ClassificationPrivate>&& pimpl);
    virtual ~Classification();
    void CheckValid() const;
    template <typename T>
    T* castImpl() {
        return static_cast<T*>(m_pimpl);
    }
    template <typename T>
    const T* castImpl() const {
        return static_cast<const T*>(m_pimpl);
    }

    ClassificationPrivate* m_pimpl;
};

} // namespace capsule::client
