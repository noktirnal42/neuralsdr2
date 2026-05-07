//
// USBDeviceMonitor.swift
// NeuralSDR2
//
// IOKit-based USB hot-plug detection for RTL-SDR devices
// Monitors USB device arrival/removal and fires callbacks
//

import Foundation
import IOKit
import IOKit.usb
import os.log

private let logger = Logger(subsystem: "com.neuralsdr2.app", category: "USBDeviceMonitor")

public class USBDeviceMonitor {

    public var onDeviceAdded: ((Int) -> Void)?
    public var onDeviceRemoved: ((Int) -> Void)?

    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var matchingDict: CFMutableDictionary?
    private let queue = DispatchQueue(label: "com.neuralsdr2.usbmonitor", qos: .utility)
    private var _isMonitoring = false

    private var trackedDevices: [UInt64: Int] = [:]
    private var deviceMapLock = os_unfair_lock_s()

    public var isMonitoring: Bool {
        return _isMonitoring
    }

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !_isMonitoring else { return }
            _isMonitoring = true

            notificationPort = IONotificationPortCreate(kIOMainPortDefault)
            guard let notifPort = notificationPort else {
                logger.error("Failed to create IOKit notification port")
                _isMonitoring = false
                return
            }

            IONotificationPortSetDispatchQueue(notifPort, queue)

            matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as CFMutableDictionary

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()

            let addResult = IOServiceAddMatchingNotification(
                notifPort,
                kIOFirstMatchNotification,
                matchingDict,
                usbDeviceAddedCallback,
                selfPtr,
                &addedIterator
            )
            if addResult != kIOReturnSuccess {
                logger.error("Failed to add arrival notification: \(addResult)")
            } else {
                enumerateInitialMatches(addedIterator, context: selfPtr)
            }

            let removeResult = IOServiceAddMatchingNotification(
                notifPort,
                kIOTerminatedNotification,
                matchingDict,
                usbDeviceRemovedCallback,
                selfPtr,
                &removedIterator
            )
            if removeResult != kIOReturnSuccess {
                logger.error("Failed to add removal notification: \(removeResult)")
            } else {
                drainIterator(removedIterator)
            }

            logger.info("USB device monitoring started")
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            guard _isMonitoring else { return }
            _isMonitoring = false

            if addedIterator != 0 {
                IOObjectRelease(addedIterator)
                addedIterator = 0
            }
            if removedIterator != 0 {
                IOObjectRelease(removedIterator)
                removedIterator = 0
            }
            if let notifPort = notificationPort {
                IONotificationPortDestroy(notifPort)
                notificationPort = nil
            }

            os_unfair_lock_lock(&deviceMapLock)
            trackedDevices.removeAll()
            os_unfair_lock_unlock(&deviceMapLock)

            logger.info("USB device monitoring stopped")
        }
    }

    private func enumerateInitialMatches(_ iterator: io_iterator_t, context: UnsafeMutableRawPointer) {
        var deviceIndex = 0
        repeat {
            let device = IOIteratorNext(iterator)
            if device != 0 {
                if isRTLSDRDevice(device) {
                    let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
                    monitor.registerDevice(device, index: deviceIndex)
                    logger.info("Initial RTL-SDR device found at index \(deviceIndex)")
                    monitor.onDeviceAdded?(deviceIndex)
                }
                deviceIndex += 1
                IOObjectRelease(device)
            }
        } while IOIteratorIsValid(iterator) != 0
    }

    private func drainIterator(_ iterator: io_iterator_t) {
        repeat {
            let device = IOIteratorNext(iterator)
            if device != 0 {
                IOObjectRelease(device)
            }
        } while IOIteratorIsValid(iterator) != 0
    }

    func handleDeviceAdded(_ iterator: io_iterator_t) {
        repeat {
            let device = IOIteratorNext(iterator)
            if device != 0 {
                if isRTLSDRDevice(device) {
                    var entryID: UInt64 = 0
                    IORegistryEntryGetRegistryEntryID(device, &entryID)

                    os_unfair_lock_lock(&deviceMapLock)
                    let existingCount = trackedDevices.count
                    trackedDevices[entryID] = existingCount
                    let index = existingCount
                    os_unfair_lock_unlock(&deviceMapLock)

                    logger.info("RTL-SDR device added (entryID: \(entryID), index: \(index))")
                    onDeviceAdded?(index)
                }
                IOObjectRelease(device)
            }
        } while IOIteratorIsValid(iterator) != 0
    }

    func handleDeviceRemoved(_ iterator: io_iterator_t) {
        repeat {
            let device = IOIteratorNext(iterator)
            if device != 0 {
                if isRTLSDRDevice(device) {
                    var entryID: UInt64 = 0
                    IORegistryEntryGetRegistryEntryID(device, &entryID)

                    os_unfair_lock_lock(&deviceMapLock)
                    let index = trackedDevices.removeValue(forKey: entryID)
                    os_unfair_lock_unlock(&deviceMapLock)

                    if let index = index {
                        logger.info("RTL-SDR device removed (entryID: \(entryID), index: \(index))")
                        onDeviceRemoved?(index)
                    }
                }
                IOObjectRelease(device)
            }
        } while IOIteratorIsValid(iterator) != 0
    }

    private func registerDevice(_ device: io_object_t, index: Int) {
        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(device, &entryID)
        os_unfair_lock_lock(&deviceMapLock)
        trackedDevices[entryID] = index
        os_unfair_lock_unlock(&deviceMapLock)
    }

    private func isRTLSDRDevice(_ device: io_object_t) -> Bool {
        var vid: Int32 = 0
        var pid: Int32 = 0

        let vidRef = IORegistryEntryCreateCFProperty(device, "idVendor" as CFString, kCFAllocatorDefault, 0)
        if let vidRef = vidRef {
            let value = vidRef.takeRetainedValue()
            if CFGetTypeID(value) == CFNumberGetTypeID() {
                CFNumberGetValue(unsafeBitCast(value, to: CFNumber.self), .sInt32Type, &vid)
            }
        }

        let pidRef = IORegistryEntryCreateCFProperty(device, "idProduct" as CFString, kCFAllocatorDefault, 0)
        if let pidRef = pidRef {
            let value = pidRef.takeRetainedValue()
            if CFGetTypeID(value) == CFNumberGetTypeID() {
                CFNumberGetValue(unsafeBitCast(value, to: CFNumber.self), .sInt32Type, &pid)
            }
        }

        let RTLSDR_VID: Int32 = 0x0BDA
        let RTLSDR_PID_2832: Int32 = 0x2832
        let RTLSDR_PID_2838: Int32 = 0x2838

        return vid == RTLSDR_VID && (pid == RTLSDR_PID_2832 || pid == RTLSDR_PID_2838)
    }
}

private func usbDeviceAddedCallback(
    _ refCon: UnsafeMutableRawPointer?,
    _ iterator: io_iterator_t
) {
    guard let refCon = refCon else { return }
    let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(refCon).takeUnretainedValue()
    monitor.handleDeviceAdded(iterator)
}

private func usbDeviceRemovedCallback(
    _ refCon: UnsafeMutableRawPointer?,
    _ iterator: io_iterator_t
) {
    guard let refCon = refCon else { return }
    let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(refCon).takeUnretainedValue()
    monitor.handleDeviceRemoved(iterator)
}
