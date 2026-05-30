import Foundation
#if os(macOS)
import Darwin.Mach
#endif

public protocol SystemPerformanceMonitor: Sendable {
    func snapshot() -> SystemPressureSnapshot
}

public struct PreviewSystemPerformanceMonitor: SystemPerformanceMonitor {
    public init() {}

    public func snapshot() -> SystemPressureSnapshot {
        SystemPressureSnapshot(memoryUsedMB: 420, physicalMemoryMB: 16_384)
    }
}

public struct FixedSystemPerformanceMonitor: SystemPerformanceMonitor {
    private let fixedSnapshot: SystemPressureSnapshot

    public init(snapshot: SystemPressureSnapshot) {
        self.fixedSnapshot = snapshot
    }

    public func snapshot() -> SystemPressureSnapshot {
        fixedSnapshot
    }
}

public struct MacSystemPerformanceMonitor: SystemPerformanceMonitor {
    public init() {}

    public func snapshot() -> SystemPressureSnapshot {
        SystemPressureSnapshot(
            thermalPressure: Self.thermalPressure(),
            memoryUsedMB: Self.currentProcessMemoryMB(),
            physicalMemoryMB: Int(ProcessInfo.processInfo.physicalMemory / 1_048_576),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    private static func thermalPressure() -> SystemPressureLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .fair
        }
    }

    private static func currentProcessMemoryMB() -> Int {
        #if os(macOS)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / 1_048_576)
        #else
        return 0
        #endif
    }
}
