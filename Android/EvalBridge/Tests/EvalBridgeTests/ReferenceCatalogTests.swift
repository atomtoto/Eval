import EvalCore
import Testing
@testable import EvalBridge

@Suite struct ReferenceCatalogTests {
    @Test func everyConstantIsListedByDomain() {
        let sections = ReferenceCatalog.constantSections()
        #expect(sections.map(\.categoryId) == ReferenceCatalog.categories().map(\.id))
        #expect(sections.first?.title == "Grandeurs fondamentales")
        #expect(sections.flatMap(\.constants).count == ConstantCatalog.all.count)
    }

    @Test func searchMatchesNamesAliasesAndDomainsIgnoringAccents() {
        let ids = { (search: String) in ReferenceCatalog.constantSections(matching: search).flatMap(\.constants).map(\.id) }
        #expect(ids("boltzmann").contains("k_B"))
        #expect(ids("electron").contains("m_e"))
        #expect(ids("kB") == ["k_B"])
        #expect(ids("introuvable").isEmpty)
        let astronomy = ReferenceCatalog.constantSections(categoryId: "astronomy")
        #expect(astronomy.map(\.title) == ["Astronomie"])
        #expect(ReferenceCatalog.constantSections(matching: "boltzmann", categoryId: "astronomy").isEmpty)
    }

    @Test func aConstantCarriesItsDetail() throws {
        let light = try #require(ReferenceCatalog.constant(id: "c"))
        #expect(light.name == "Vitesse de la lumière")
        #expect(light.valueText.hasPrefix("299792458 "))
        #expect(light.natureTitle == "Exacte" && light.nature == "exact")
        #expect(light.sourceUrl?.hasPrefix("https://") == true)
        #expect(light.aliases.contains("c0"))
        #expect(light.spokenLine.contains("égale"))
        #expect(ReferenceCatalog.constant(id: "ε0")?.id == "epsilon_0")
        #expect(ReferenceCatalog.constant(id: "inconnue") == nil)
    }

    @Test func unitsAreSearchedBySymbolOrName() {
        #expect(ReferenceCatalog.units().count == UnitCatalog.all.count)
        let kilometre = ReferenceCatalog.units(matching: "kilometre")
        #expect(kilometre.map(\.symbol) == ["km"])
        #expect(kilometre.first?.valueText == "1000 m")
        #expect(ReferenceCatalog.units(matching: "Ω").map(\.symbol).contains("Ω"))
    }
}

@Suite struct FormattingTests {
    @Test func snippetsAreInsertedAtUTF16Offsets() throws {
        let plus = try #require(FormulaInserter.insert(kind: "operator", argument: "+", text: "a", selectionStart: 1, selectionEnd: 1))
        #expect(plus.text == "a + " && plus.caret == 4)
        let root = try #require(FormulaInserter.insert(kind: "function", argument: "sqrt", text: "x = 2", selectionStart: 4,
                                                       selectionEnd: 5))
        #expect(root.text == "x = sqrt(2)" && root.caret == 11)
        let fraction = try #require(FormulaInserter.insert(kind: "fraction", text: "", selectionStart: 0, selectionEnd: 0))
        #expect(fraction.text == "()/()" && fraction.caret == 1)
        // 𝑣 takes two UTF-16 units.
        let pi = try #require(FormulaInserter.insert(kind: "name", argument: "π", text: "𝑣 = 1", selectionStart: 2, selectionEnd: 2))
        #expect(pi.text == "𝑣 * π = 1" && pi.caret == 6)
        #expect(FormulaInserter.insert(kind: "inconnu", text: "a", selectionStart: 0, selectionEnd: 0) == nil)
    }

    @Test func numbersAreWrittenAndReadWithADecimalComma() {
        #expect(NumberText.parse(" −2,5 ") == -2.5)
        #expect(NumberText.parse("1.5") == 1.5)
        #expect(NumberText.parse("abc") == nil)
        #expect(NumberText.editable(0.05) == "0,05")
        #expect(NumberText.editable(200) == "200")
        #expect(NumberText.editable(1e-20) == "0,00000000000000000001")
        #expect(NumberText.format(45, unit: "°", precise: false) == "45°")
        #expect(NumberText.format(80, unit: "kg", precise: true) == "80 kg")
        #expect(NumberText.spoken(81, unit: "kg", precise: true).contains("kilogrammes"))
        #expect(SheetEditor.steppedValue(from: 8.2, steps: 1, step: 0.1) == 8.3)
    }

    @Test func significantDigitsAreClamped() {
        #expect(EvalSettings.minimumSignificantDigits == 3 && EvalSettings.maximumSignificantDigits == 12)
        #expect(EvalSettings.defaultSignificantDigits == 6)
    }
}
