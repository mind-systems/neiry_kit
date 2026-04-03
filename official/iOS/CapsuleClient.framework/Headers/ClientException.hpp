// Copyright. 2019 - 2024 PSBD. All rights reserved.

#pragma once

#include <stdexcept>
#include <string>

namespace capsule::client {
/**
 * This is a generic exception for Capsule's client side.
 */
class ClientException : public std::runtime_error {
    std::string m_reason = "Client exception: ";

  public:
    explicit ClientException(std::string_view exceptionReason) noexcept
    : runtime_error(exceptionReason.data()) {
        m_reason.append(exceptionReason);
    }

    const char* what() const noexcept override {
        return m_reason.c_str();
    }
};
} // namespace capsule::client
