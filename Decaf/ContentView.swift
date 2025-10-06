//
//  ContentView.swift
//  Decaf
//
//  Created by nullptr on 20/09/2025.
//

import SwiftUI

struct ContentView: View {
    @State public var isKeepingAwake: Bool = false
    @State private var caffeinateTask: Process? = nil
    
    // MARK: - Process control
    
    private func startCaffeinate() {
        if let process = caffeinateTask, process.isRunning { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-i"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
#if DEBUG
            print("Launching caffeinate")
#endif
            try process.run()
            caffeinateTask = process
        } catch {
            caffeinateTask = nil
            isKeepingAwake = false
#if DEBUG
            print("Failed to start caffeinate: \(error)")
#endif
        }
    }
    
    private func stopCaffeinate() {
#if DEBUG
        print("Stopping caffeinate")
#endif
        guard let process = caffeinateTask else { return }
        if process.isRunning {
            process.terminate()
        }
        caffeinateTask = nil
        isKeepingAwake = false
    }
    
    // MARK: - View
    
    var body: some View {
        Toggle("Keep awake", isOn: $isKeepingAwake)
            .onChange(of: isKeepingAwake) { _, newValue in
                if newValue {
                    startCaffeinate()
                } else {
                    stopCaffeinate()
                }
            }
            .onAppear {
                // Ensure UI reflects any prior state if needed
                if isKeepingAwake {
                    startCaffeinate()
                }
            }
            .onDisappear {
                stopCaffeinate()
            }
        
        Button("Quit") {
            // Ensure we stop caffeinate before quitting
            stopCaffeinate()
            NSApp.terminate(nil)
        }
    }
}

//#Preview {
//    ContentView()
//}
