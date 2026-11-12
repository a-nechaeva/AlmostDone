import SwiftUI

struct RecipeStepsScreen: View {
    @ScaledMetric(relativeTo: .subheadline) private var numberSize = 32.0
    let title: String
    let servings: RecipePresentation.Servings?
    let steps: [RecipePresentation.Step]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Как приготовить")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                VStack(spacing: 16) {
                    ForEach(steps.indices, id: \.self) { index in
                        stepCard(steps[index])
                    }
                }
                .padding(.top, 48)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.demoBackground).ignoresSafeArea())
        .navigationTitle("Рецепт")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var subtitle: String {
        guard let servings else { return title }
        return "\(title) · \(servings.description)"
    }

    private func stepCard(_ step: RecipePresentation.Step) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(step.number)")
                .font(.subheadline.bold())
                .foregroundStyle(Color.accentColor)
                .frame(minWidth: numberSize, minHeight: numberSize)
                .background(Color.accentColor.opacity(0.14), in: .capsule)

            VStack(alignment: .leading, spacing: 6) {
                Text(step.text)
                    .font(.subheadline)
                if let minutes = step.minutes {
                    Text("\(minutes) мин")
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.top, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(minHeight: 114, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recipe.step.\(step.number)")
    }
}
