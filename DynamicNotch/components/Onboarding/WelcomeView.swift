//
//  WelcomeView.swift
//  DynamicNotch
//

import SwiftUI

struct WelcomeView: View {
    var onGetStarted: (() -> Void)? = nil

    private let violet = Color(red: 0.78, green: 0.46, blue: 1.0)
    private let background = Color(red: 0.035, green: 0.025, blue: 0.065)

    var body: some View {
        ZStack {
            background

            Image("WelcomeArtwork")
                .resizable()
                .scaledToFill()
                .frame(width: 400, height: 600)
                .clipped()
                .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: background.opacity(0.72), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .clear, location: 0.52),
                    .init(color: background.opacity(0.86), location: 0.75),
                    .init(color: background, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Text("WELCOME TO")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(violet)
                    .padding(.top, 48)

                Text("DynamicNotch")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 10)

                Spacer()

                Text("Make more of your notch.")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Music, controls, and the things you need, right where you need them.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 44)
                    .padding(.top, 12)

                Button {
                    onGetStarted?()
                } label: {
                    HStack(spacing: 10) {
                        Text("Get started")
                            .font(.system(size: 15, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.57, green: 0.30, blue: 0.84),
                                     Color(red: 0.42, green: 0.20, blue: 0.70)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(violet.opacity(0.55), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.horizontal, 44)
                .padding(.top, 30)
                .padding(.bottom, 48)
            }
        }
        .frame(width: 400, height: 600)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

#Preview {
    WelcomeView()
}
