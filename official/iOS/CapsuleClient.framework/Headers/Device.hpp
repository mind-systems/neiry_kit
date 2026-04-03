// Copyright. 2019 - 2024 PSBD. All rights reserved.

#pragma once

#include "CDefinesPrivate.h"

#include <Devices/DeviceTypes.hpp>
#include <Utils/Time.hpp>

#include <string>

namespace capsule::client {
class ClientPrivate;
class Device;
class DevicePrivate;
class DeviceLocatorPrivate;

/**
 * \brief Device locator.
 *
 * Searches for available devices of chosen type
 */
class CL_DLL DeviceLocator final {
    friend ClientPrivate;
    friend Device;
    friend DevicePrivate;
    friend DeviceLocatorPrivate;

  public:
    explicit DeviceLocator(const std::optional<fs::path>& logDirectory = std::nullopt);
    DeviceLocator(const DeviceLocator&) = delete;
    DeviceLocator& operator=(const DeviceLocator&) = delete;
    DeviceLocator(DeviceLocator&& rhd) noexcept;
    DeviceLocator& operator=(DeviceLocator&& rhd) noexcept;
    ~DeviceLocator();
    /**
     * \brief Find available devices. Search time is in seconds.
     * Non-blocking - OnDevices event is fired when timeout expires.
     *
     * \param deviceType
     * \param searchTime search time in seconds
     */
    void RequestDevices(device::DeviceType deviceType, core::SecondsI searchTime);
    /**
     * Create device for interaction.
     *
     * \param deviceSerial device ID string
     * \returns device
     */
    Device CreateDevice(const std::string& deviceSerial) &;

    void SetOnDevicesEvent(std::function<void(DeviceLocator&, const device::DeviceListExpected&)>&& callback);

    static void SetSingleThreaded(bool singleThreaded);
    void Update();

    bool IsValid() const noexcept;
    void ResetDevice();

  private:
    void CheckValid() const;

    std::unique_ptr<DeviceLocatorPrivate> m_pimpl;
};

/**
 * \brief Device.
 *
 * Controls connection to the device
 */
class CL_DLL Device final {
    friend DeviceLocator;
    friend DeviceLocatorPrivate;
    friend ClientPrivate;
    friend DevicePrivate;

  public:
    Device(const Device&) = delete;
    Device& operator=(const Device&) = delete;
    Device(Device&& rhd) noexcept;
    Device& operator=(Device&& rhd) noexcept;
    ~Device() = default;
    /**
     * Is device connected to Capsule.
     */
    bool IsConnected() const;
    /**
     * Get device information.
     * \returns device info
     */
    const device::DeviceInfo& GetInfo() &;
    float GetEEGSampleRate() const;
    float GetPPGSampleRate() const;
    float GetMEMSSampleRate() const;
    int GetPPGIrAmplitude() const;
    int GetPPGRedAmplitude() const;

    void SetOnConnectionStateChangedEvent(std::function<void(Device&, device::DeviceConnectionStatus)>&& callback);
    void SetOnResistanceUpdateEvent(std::function<void(Device&, device::Resistances&&)>&& callback);
    void SetOnBatteryChargeUpdateEvent(std::function<void(Device&, device::DeviceBatteryCharge)>&& callback);
    void SetOnEEGDataEvent(std::function<void(Device&, device::EEGTimedData&&)>&& callback);
    void SetOnErrorEvent(std::function<void(Device&, std::string&&)>&& callback);
    void SetOnModeSwitchedEvent(std::function<void(Device&, device::DeviceMode)>&& callback);
    void SetOnPSDDataEvent(std::function<void(Device&, device::PSDData&&)>&& callback);
    void SetOnEEGArtifactsEvent(std::function<void(Device&, device::EEGArtifacts&&)>&& callback);

    /**
     * Connect to device. Non-blocking - OnConnectionStateChanged event is
     * fired when connected.
     */
    void Connect(bool bipolarChannels);
    /**
     * Disconnect from device. Non-blocking - OnConnectionStateChanged
     * event is fired when disconnected.
     */
    void Disconnect();
    void Start();
    bool Stop();

    device::DeviceBatteryCharge GetBatteryCharge() const;
    device::DeviceChannelNames GetChannelNames() const;
    device::DeviceMode GetMode() const;

    bool IsValid() const noexcept;

  private:
    void CheckValid() const;
    Device() = default;

    DevicePrivate* m_pimpl = nullptr;
};

} // namespace capsule::client
