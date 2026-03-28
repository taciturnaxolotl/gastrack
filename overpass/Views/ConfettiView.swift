import SwiftUI

struct ConfettiView: View {
    struct Particle: Identifiable {
        let id = UUID()
        let x: CGFloat
        let color: Color
        let width: CGFloat
        let height: CGFloat
        let delay: Double
        let duration: Double
        let targetRotation: Double
        let drift: CGFloat
    }

    private static let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .cyan]

    private let particles: [Particle] = (0..<90).map { _ in
        Particle(
            x: CGFloat.random(in: 0...1),
            color: colors[Int.random(in: 0..<colors.count)],
            width: CGFloat.random(in: 6...12),
            height: CGFloat.random(in: 8...16),
            delay: Double.random(in: 0...1.8),
            duration: Double.random(in: 2...3.5),
            targetRotation: Double.random(in: 180...540),
            drift: CGFloat.random(in: -60...60)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                ParticleView(particle: p, screenSize: geo.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct ParticleView: View {
    let particle: ConfettiView.Particle
    let screenSize: CGSize

    @State private var offsetY: CGFloat = 0
    @State private var offsetX: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 0

    var body: some View {
        Rectangle()
            .fill(particle.color)
            .frame(width: particle.width, height: particle.height)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .position(x: particle.x * screenSize.width + offsetX, y: -20 + offsetY)
            .onAppear {
                withAnimation(.easeIn(duration: 0.15).delay(particle.delay)) {
                    opacity = 1
                }
                withAnimation(.linear(duration: particle.duration).delay(particle.delay)) {
                    offsetY = screenSize.height + 40
                    offsetX = particle.drift
                    rotation = particle.targetRotation
                }
                withAnimation(.easeOut(duration: 0.4).delay(particle.delay + particle.duration - 0.4)) {
                    opacity = 0
                }
            }
    }
}
