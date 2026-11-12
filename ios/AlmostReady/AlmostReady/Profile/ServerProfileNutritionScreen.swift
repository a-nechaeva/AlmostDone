import SwiftUI

struct ServerProfileNutritionScreen: View {
    let model: ServerProfileModel

    var body: some View {
        ProfileForm(title: "Питание и аллергены") {
            ProfileHeading(title: "Предпочтения питания")
            VStack(alignment: .leading, spacing: 20) {
                if let draft = model.draft, let catalogs = model.catalogs {
                    choices(draft: draft.preferences, catalogs: catalogs)
                        .disabled(!model.canEdit)
                    ProfileNotice(
                        title: "Проверяйте состав продуктов",
                        message: "Сведения об аллергенах могут быть неполными."
                    )
                }
                status
                if model.canEdit {
                    ProfileRetryControl(deadline: model.retryAfter) {
                        ProfileSaveButton(title: "Сохранить предпочтения") {
                            Task { await model.save() }
                        }
                        .disabled(!model.canSave)
                        .opacity(model.canSave ? 1 : 0.5)
                    }
                }
                if model.phase != .saving {
                    Button("Отмена", action: model.closeEditor)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.top, 24)
        }
        .navigationBarBackButtonHidden(model.phase == .saving)
    }

    private func choices(draft: ProfilePreferences, catalogs: ProfileCatalogs) -> some View {
        let groups = DietaryGroups(options: catalogs.dietary)
        let unsupported = Set(model.draft?.base.value.unsupportedRestrictions ?? [])
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Тип питания")
                    .font(.callout.bold())
                    .accessibilityAddTraits(.isHeader)
                ForEach(groups.foodTypes) { option in
                    dietaryChoice(option, draft: draft, unsupported: unsupported)
                }
            }

            NavigationLink {
                ProfileForm(title: "Аллергены") {
                    ProfileHeading(title: "Что исключить?")
                    if catalogs.allergens.isEmpty {
                        Text("В справочнике пока нет аллергенов")
                    }
                    ForEach(catalogs.allergens) { allergen in
                        if allergen.support == .informational {
                            Text(allergen.name).foregroundStyle(.secondary)
                        } else {
                            ProfileChoiceRow(
                                title: optionTitle(allergen.name, unsupported: allergen.support == .unsupported),
                                isSelected: model.draft?.preferences.excludedAllergens.contains(allergen.id) == true
                            ) {
                                model.edit {
                                    if $0.excludedAllergens.remove(allergen.id) == nil {
                                        $0.excludedAllergens.insert(allergen.id)
                                    }
                                }
                            }
                        }
                    }
                    ProfileNotice(
                        title: "Сведения могут быть неполными",
                        message: "Отсутствие записи об аллергене не подтверждает его отсутствие."
                    )
                }
            } label: {
                ProfileMenuRow(title: "Аллергены", subtitle: allergenSummary(draft, catalogs: catalogs))
            }
            .buttonStyle(.plain)

            ForEach(groups.restrictions) { option in
                dietaryChoice(option, draft: draft, unsupported: unsupported)
            }

            NavigationLink {
                ProfileForm(title: "Диетический стол") {
                    ProfileHeading(title: "Диетический стол")
                    ProfileChoiceRow(
                        title: "Без диетического стола",
                        isSelected: model.draft?.preferences.dietTableID == nil,
                        isSingleChoice: true
                    ) {
                        model.edit { $0.dietTableID = nil }
                    }
                    if let current = model.draft?.preferences {
                        ForEach(groups.dietTables) { option in
                            dietaryChoice(option, draft: current, unsupported: unsupported)
                        }
                    }
                }
            } label: {
                ProfileMenuRow(
                    title: "Диетический стол",
                    subtitle: dietTableSummary(draft, options: groups.dietTables, unsupported: unsupported)
                )
            }
            .buttonStyle(.plain)

            ForEach(groups.information) { option in
                Text(option.name).foregroundStyle(.secondary)
            }
            let missing = unsupported.subtracting(catalogs.dietary.map(\.id)).sorted()
            if !missing.isEmpty {
                Text("Подбор не учитывает ограничения: \(missing.joined(separator: ", "))")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .loading:
            ProgressView("Загружаем настройки…")
        case .loadFailed:
            Text("Не удалось загрузить настройки")
            ProfileRetryControl(deadline: model.retryAfter) {
                Button("Повторить") { Task { await model.loadEditor() } }
            }
        case .closed, .editing:
            EmptyView()
        case .saving:
            ProgressView("Сохраняем настройки…")
        case .saveFailed:
            Text("Не удалось сохранить настройки. Черновик сохранён")
        case .reloadingConflict:
            ProgressView("Обновляем настройки с сервера…")
        case .conflictReloadFailed:
            Text("Настройки изменились. Не удалось загрузить сохранённую версию")
            ProfileRetryControl(deadline: model.retryAfter) {
                Button("Загрузить сохранённую версию") { Task { await model.reloadConflict() } }
            }
        case .conflictReady:
            if let conflict = model.conflict?.value, let catalogs = model.catalogs {
                ProfileNotice(
                    title: "Настройки изменились",
                    message: "Сверьте настройки с сервера со своим черновиком перед сохранением."
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("Сохранено на сервере").font(.callout.bold())
                    Text(summary(of: conflict, catalogs: catalogs))
                        .font(.footnote)
                }
                Button("Перенести мои изменения", action: model.reconcileConflict)
            }
        }
    }

    @ViewBuilder private func dietaryChoice(
        _ option: ProfileDietaryOption, draft: ProfilePreferences, unsupported: Set<String>
    ) -> some View {
        if let binding = option.binding {
            ProfileChoiceRow(
                title: optionTitle(
                    option.name, unsupported: option.support == .unsupported || unsupported.contains(option.id)),
                isSelected: binding.isSelected(in: draft), isSingleChoice: binding.isSingleChoice
            ) {
                model.edit { binding.select(in: &$0) }
            }
        }
    }

    private func optionTitle(_ name: String, unsupported: Bool) -> String {
        unsupported ? "\(name) · Не учитывается в подборе" : name
    }

    private func allergenSummary(_ preferences: ProfilePreferences, catalogs: ProfileCatalogs) -> String {
        let names = preferences.excludedAllergens.sorted().map { id in
            guard let option = catalogs.allergens.first(where: { $0.id == id }) else { return id }
            return optionTitle(option.name, unsupported: option.support == .unsupported)
        }
        return names.isEmpty ? "Не выбраны" : names.joined(separator: ", ")
    }

    private func dietTableSummary(
        _ preferences: ProfilePreferences, options: [ProfileDietaryOption], unsupported: Set<String>
    ) -> String {
        guard let id = preferences.dietTableID else { return "Не выбран" }
        guard let option = options.first(where: { $0.binding?.isSelected(in: preferences) == true }) else { return id }
        return optionTitle(option.name, unsupported: option.support == .unsupported || unsupported.contains(option.id))
    }

    private func summary(of profile: ServerProfile, catalogs: ProfileCatalogs) -> String {
        let selected = catalogs.dietary.filter { $0.binding?.isSelected(in: profile.preferences) == true }
        let restrictions = selected.map {
            optionTitle(
                $0.name, unsupported: $0.support == .unsupported || profile.unsupportedRestrictions.contains($0.id))
        }
        return (restrictions + ["Аллергены: \(allergenSummary(profile.preferences, catalogs: catalogs))"])
            .joined(separator: "\n")
    }

    private struct DietaryGroups {
        var foodTypes: [ProfileDietaryOption] = []
        var restrictions: [ProfileDietaryOption] = []
        var dietTables: [ProfileDietaryOption] = []
        var information: [ProfileDietaryOption] = []

        init(options: [ProfileDietaryOption]) {
            for option in options {
                switch option.binding {
                case .foodType: foodTypes.append(option)
                case .restriction: restrictions.append(option)
                case .dietTable: dietTables.append(option)
                case nil: information.append(option)
                }
            }
        }
    }
}
