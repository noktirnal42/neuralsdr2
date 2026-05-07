//
// RDSDataPanel.swift
// NeuralSDR2
//
// Panel displaying decoded RDS data from FM broadcast
//

import SwiftUI

public struct RDSDataPanel: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RDS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
                Circle()
                    .fill(appState.rdsData.stationName.isEmpty ? Color.gray : Color.green)
                    .frame(width: 6, height: 6)
                Spacer()
            }

            if appState.rdsData.stationName.isEmpty && appState.rdsData.radioText.isEmpty {
                Text("No RDS Data")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                if !appState.rdsData.stationName.isEmpty {
                    Text(appState.rdsData.stationName)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                }

                if !appState.rdsData.radioText.isEmpty {
                    Text(appState.rdsData.radioText)
                        .font(.system(size: 11))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                HStack(spacing: 12) {
                    if appState.rdsData.piCode != 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PI")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(String(format: "%04X", appState.rdsData.piCode))
                                .font(.system(size: 11).monospaced())
                        }
                    }

                    if !appState.rdsData.programType.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PTY")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(appState.rdsData.programType)
                                .font(.system(size: 11))
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            IndicatorLight(on: appState.rdsData.trafficProgram, label: "TP", color: .green)
                            IndicatorLight(on: appState.rdsData.trafficAnnouncement, label: "TA", color: .orange)
                        }
                        HStack(spacing: 4) {
                            IndicatorLight(on: appState.rdsData.isMusic, label: "Music", color: .blue)
                            IndicatorLight(on: !appState.rdsData.isMusic && appState.rdsData.hasData, label: "Speech", color: .purple)
                        }
                    }
                }

                if !appState.rdsData.alternativeFrequencies.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alt. Freq.")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(appState.rdsData.alternativeFrequencies, id: \.self) { freq in
                                    Button(String(format: "%.1f", freq)) {
                                        appState.setFrequency(Double(freq) * 1_000_000)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

private struct IndicatorLight: View {
    let on: Bool
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(on ? color : Color.gray.opacity(0.3))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(on ? .primary : .secondary)
        }
    }
}
