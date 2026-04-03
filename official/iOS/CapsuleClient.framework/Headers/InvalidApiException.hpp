// Copyright. 2019 - 2024 PSBD. All rights reserved.

#pragma once

#include "ClientException.hpp"

#include <string>

namespace capsule::client {
/**
 * Exception for CheckValid() member functions for Capsule's client side.
 */
class InvalidApiException final : public ClientException {
    constexpr static char s_delimiter = '\n';
    constexpr static std::string_view s_prefix = "Invalid source: ";
    std::string m_reasonWithSource;

  public:
    InvalidApiException(std::string_view exceptionReason, std::string_view invalidSource) noexcept
    : ClientException(exceptionReason) {
        m_reasonWithSource.append(ClientException::what()).push_back(s_delimiter);
        m_reasonWithSource.append(s_prefix).append(invalidSource);
    }

    const char* what() const noexcept override {
        return m_reasonWithSource.c_str();
    }
};
} // namespace capsule::client
