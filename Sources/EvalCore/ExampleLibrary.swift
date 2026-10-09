import Foundation

/// The subject of an example sheet, in presentation order.
public enum ExampleDomain: String, CaseIterable, Identifiable, Sendable {
    case mechanics, electricity, optics, thermodynamics, quantum, astronomy, method

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mechanics: "Mécanique"
        case .electricity: "Électricité"
        case .optics: "Optique et ondes"
        case .thermodynamics: "Thermodynamique"
        case .quantum: "Quantique"
        case .astronomy: "Astronomie"
        case .method: "Méthode"
        }
    }
}

/// A ready-made sheet. Its source follows the convention of the app: a `# Titre`
/// comment first, then declarations, then the lines whose results matter. A line
/// ends with `=` to show its value (`d =`, `v → km/h =`, `E = 0,5 * m * v² =`);
/// without it, a formula or a declaration shows nothing.
public struct ExampleSheet: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let domain: ExampleDomain
    public let summary: String
    public let source: String
}

/// Examples checked by the test suite: each one evaluates without an unexpected
/// error and its key values are pinned.
public enum ExampleLibrary: Sendable {
    public static let all: [ExampleSheet] = [
        ExampleSheet(id: "free-fall", title: "Chute libre", domain: .mechanics,
                     summary: "Distance et vitesse après 3 s de chute, avec g.", source: """
            # Chute libre depuis le repos, sans frottement
            d = 0,5 * g * t²
            v = g * t
            t = 3 s

            d =
            v =
            # → km/h choisit l’unité d’affichage ; le = final affiche la valeur
            v → km/h =
            """),
        ExampleSheet(id: "kinetic-energy", title: "Énergie cinétique", domain: .mechanics,
                     summary: "Énergie d’une masse en mouvement.", source: """
            # Énergie cinétique
            E = 0,5 * m * v²
            m = 80 kg
            v = 5 m/s

            E =
            # La vitesse de la lumière est reconnue
            c =
            """),
        ExampleSheet(id: "projectile", title: "Tir sans frottement", domain: .mechanics,
                     summary: "Portée, hauteur et durée d’un tir incliné.", source: """
            # Tir sans frottement depuis le sol
            v0 = 20 m/s
            theta = 45 deg
            portee = v0² * sin(2 * theta) / g
            h_max = (v0 * sin(theta))² / (2 * g)
            duree = 2 * v0 * sin(theta) / g

            portee =
            h_max =
            duree =
            """),
        ExampleSheet(id: "pendulum", title: "Pendule simple", domain: .mechanics,
                     summary: "Période des petites oscillations.", source: """
            # Pendule simple, petites oscillations
            T = 2 * pi * sqrt(l / g)
            l = 1 m

            T =
            """),
        ExampleSheet(id: "spring", title: "Oscillateur masse-ressort", domain: .mechanics,
                     summary: "Période et fréquence d’une masse au bout d’un ressort.", source: """
            # Oscillateur masse-ressort
            T = 2 * pi * sqrt(m / k)
            f = 1 / T
            m = 0,5 kg
            # k déclaré ici remplace la constante de Boltzmann
            k = 200 N/m

            T =
            f → Hz =
            """),
        ExampleSheet(id: "relativity", title: "Dilatation du temps", domain: .mechanics,
                     summary: "Facteur de Lorentz à 80 % de la vitesse de la lumière.", source: """
            # Dilatation du temps à 80 % de c
            v = 0,8 * c
            gamma = 1 / sqrt(1 - v² / c²)

            gamma =
            v → km/s =
            """),
        ExampleSheet(id: "heater", title: "Radiateur électrique", domain: .electricity,
                     summary: "Courant, puissance et énergie consommée en 2 h.", source: """
            # Radiateur électrique
            U = 230 V
            R = 52,9 Ω
            I = U / R
            P = U * I
            E = P * 2 h

            I =
            P =
            E → kWh =
            """),
        ExampleSheet(id: "rc-circuit", title: "Circuit RC", domain: .electricity,
                     summary: "Constante de temps et tension d’un condensateur qui se charge.", source: """
            # Charge d’un condensateur (circuit RC)
            R = 10 kΩ
            C = 100 µF
            U0 = 12 V
            t = 1 s
            tau = R * C
            U_C = U0 * (1 - exp(-t / tau))

            tau =
            U_C =
            """),
        ExampleSheet(id: "coulomb", title: "Force électrostatique", domain: .electricity,
                     summary: "Force entre deux charges ponctuelles.", source: """
            # Force électrostatique entre deux charges
            q1 = 2 µC
            q2 = -3 µC
            r = 5 cm
            F = k_e * q1 * q2 / r²

            # Une valeur négative indique une attraction
            F =
            """),
        ExampleSheet(id: "lens", title: "Lentille convergente", domain: .optics,
                     summary: "Position et grandissement de l’image.", source: """
            # Image par une lentille convergente
            f = 50 mm
            d_o = 2 m
            d_i = 1 / (1 / f - 1 / d_o)
            gamma = -d_i / d_o

            d_i =
            gamma =
            """),
        ExampleSheet(id: "young", title: "Fentes d’Young", domain: .optics,
                     summary: "Interfrange d’une figure d’interférences.", source: """
            # Interfrange des fentes d’Young
            lambda = 650 nm
            D = 2 m
            a = 0,1 mm
            i = lambda * D / a

            i → mm =
            """),
        ExampleSheet(id: "ideal-gas", title: "Gaz parfait", domain: .thermodynamics,
                     summary: "Pression d’une mole de gaz dans 24 L.", source: """
            # Pression d’un gaz parfait
            n = 1 mol
            T = 293,15 K
            V = 24 L
            p = n * R * T / V

            p → atm =
            """),
        ExampleSheet(id: "water-heating", title: "Chauffer de l’eau", domain: .thermodynamics,
                     summary: "Énergie et durée pour chauffer 1,5 kg d’eau de 80 K.", source: """
            # Chauffer de l’eau, sans pertes
            m = 1,5 kg
            c_eau = 4180 J/kg/K
            ΔT = 80 K
            Q = m * c_eau * ΔT
            P = 2 kW
            duree = Q / P

            Q → kJ =
            duree → min =
            """),
        ExampleSheet(id: "black-body", title: "Le Soleil, corps noir", domain: .thermodynamics,
                     summary: "Longueur d’onde du maximum et exitance du Soleil.", source: """
            # Le Soleil comme corps noir
            T = 5772 K
            lambda_max = b_Wien / T
            M = sigma_SB * T⁴

            lambda_max → nm =
            M → W/m² =
            """),
        ExampleSheet(id: "electron", title: "Électron accéléré", domain: .quantum,
                     summary: "Vitesse et longueur d’onde de de Broglie sous 100 V.", source: """
            # Électron accéléré sous 100 V
            U = 100 V
            v = sqrt(2 * e * U / m_e)
            lambda = h / (m_e * v)

            v → km/s =
            lambda → pm =
            """),
        ExampleSheet(id: "photoelectric", title: "Effet photoélectrique", domain: .quantum,
                     summary: "Énergie cinétique des électrons arrachés au sodium.", source: """
            # Effet photoélectrique sur le sodium
            W = 2,28 eV
            lambda = 400 nm
            E_c = h * c / lambda - W

            E_c → eV =
            """),
        ExampleSheet(id: "hydrogen", title: "Raie Hα", domain: .quantum,
                     summary: "Longueur d’onde de la transition 3 → 2 de l’hydrogène.", source: """
            # Raie Hα de l’hydrogène (noyau de masse infinie)
            E_3 = -E_h / (2 * 3²)
            E_2 = -E_h / (2 * 2²)
            lambda = h * c / (E_3 - E_2)

            lambda → nm =
            """),
        ExampleSheet(id: "light-energy", title: "Énergie et lumière", domain: .quantum,
                     summary: "Énergie d’un photon de 550 nm.", source: """
            # Énergie d’un photon
            E = h * c / lambda
            lambda = 550 nm

            E → eV =
            # h et c sont des constantes reconnues
            c / lambda → THz =
            """),
        ExampleSheet(id: "kepler", title: "Troisième loi de Kepler", domain: .astronomy,
                     summary: "Période de la Terre autour du Soleil.", source: """
            # Troisième loi de Kepler : période de la Terre
            a = 1 au
            T = 2 * pi * sqrt(a³ / GM_sun_N)

            T =
            # En jours
            T → jour =
            """),
        ExampleSheet(id: "escape-velocity", title: "Vitesse de libération", domain: .astronomy,
                     summary: "Vitesse pour quitter l’attraction terrestre.", source: """
            # Vitesse de libération terrestre
            v_lib = sqrt(2 * GM_earth_N / R_earth_equatorial_N)

            v_lib → km/s =
            """),
        ExampleSheet(id: "geostationary", title: "Orbite géostationnaire", domain: .astronomy,
                     summary: "Rayon et altitude d’une orbite de période 86 164,1 s.", source: """
            # Orbite géostationnaire
            T = 86164,1 s
            r = (GM_earth_N * T² / (4 * pi²))^(1/3)
            altitude = r - R_earth_equatorial_N

            r =
            altitude → km =
            """),
        ExampleSheet(id: "dimensions", title: "Vérifier les dimensions", domain: .method,
                     summary: "Une égalité homogène, puis une addition impossible.", source: """
            # Les deux côtés ont la dimension d’une force
            m * a == F
            F = 14,4 N
            a = 7,2 m/s²
            m = 2 kg

            # Cette addition est impossible physiquement ; une erreur s’affiche même sans =
            2 m + 3 s
            """),
        ExampleSheet(id: "solve-unknown", title: "Trouver une inconnue", domain: .method,
                     summary: "Quelle vitesse donne 1000 J d’énergie cinétique ? Eval la cherche.", source: """
            # Quelle vitesse donne 1000 J d’énergie cinétique ?
            E = 1000 J
            m = 80 kg
            # « ? » demande à Eval de trouver v pour que la relation == soit vraie
            v = ? m/s
            E == 0,5 * m * v²

            # L’autre solution (-5 m/s) est indiquée sur la ligne de v
            v → km/h =
            """)
    ]

    public static func examples(in domain: ExampleDomain) -> [ExampleSheet] {
        all.filter { $0.domain == domain }
    }

    public static func example(id: String) -> ExampleSheet? {
        all.first { $0.id == id }
    }
}
