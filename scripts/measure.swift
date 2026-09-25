// 资源占用测试：读取某个进程的内存占用、CPU 时间和唤醒次数（系统的 proc_pid_rusage 接口，不需要调试权限）。
// 用法：swift scripts/measure.swift <pid>
// 输出一行：footprint_mb=… cpu_s=… idle_wakeups=… interrupt_wakeups=…
import Darwin

guard CommandLine.arguments.count > 1, let pid = pid_t(CommandLine.arguments[1]) else {
    print("用法：swift scripts/measure.swift <pid>")
    exit(2)
}

var info = rusage_info_v4()
let result = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
    }
}
guard result == 0 else {
    print("无法读取进程 \(pid) 的资源占用")
    exit(1)
}

// CPU 时间的单位是 mach 时钟周期，需要换算成秒
var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
let ticks = Double(info.ri_user_time + info.ri_system_time)
let cpuSeconds = ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000

let footprint = Double(info.ri_phys_footprint) / 1_048_576
print(String(format: "footprint_mb=%.1f cpu_s=%.3f idle_wakeups=%llu interrupt_wakeups=%llu",
             footprint, cpuSeconds, info.ri_pkg_idle_wkups, info.ri_interrupt_wkups))
