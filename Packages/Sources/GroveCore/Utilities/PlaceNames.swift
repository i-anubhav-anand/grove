import Foundation

/// Branch/worktree names are drawn from a built-in list of place names (à la
/// Conductor's `missoula`, `sarajevo`, …) instead of the prompt text — short,
/// memorable, and decoupled from what the chat is about. Fully local, no network.
public enum PlaceNames {
    /// Lowercase, single-token, branch-safe place names.
    public static let all: [String] = [
        "moscow", "sarajevo", "missoula", "raleigh", "philadelphia", "davao", "riga",
        "surabaya", "adelaide", "miami", "lisbon", "porto", "oslo", "bergen", "helsinki",
        "tampere", "tallinn", "vilnius", "krakow", "gdansk", "prague", "brno", "vienna",
        "graz", "zurich", "geneva", "bern", "milan", "turin", "naples", "bologna", "verona",
        "seville", "valencia", "bilbao", "granada", "malaga", "cordoba", "toledo", "nantes",
        "lyon", "marseille", "bordeaux", "toulouse", "nice", "lille", "rennes", "dijon",
        "bremen", "leipzig", "dresden", "cologne", "munich", "hamburg", "stuttgart",
        "athens", "patras", "thessaloniki", "izmir", "ankara", "bursa", "antalya", "konya",
        "cairo", "luxor", "tangier", "fez", "rabat", "tunis", "dakar", "accra", "lagos",
        "nairobi", "kampala", "kigali", "lusaka", "harare", "gaborone", "windhoek", "maputo",
        "durban", "pretoria", "kyoto", "osaka", "nagoya", "sapporo", "sendai", "fukuoka",
        "busan", "incheon", "daegu", "taipei", "kaohsiung", "manila", "cebu", "bandung",
        "medan", "hanoi", "hue", "vientiane", "phnom", "yangon", "mandalay", "colombo",
        "kandy", "chennai", "kochi", "mysore", "pune", "nagpur", "indore", "jaipur",
        "udaipur", "shimla", "manali", "leh", "gangtok", "shillong", "kabul", "herat",
        "tashkent", "samarkand", "almaty", "bishkek", "tbilisi", "yerevan", "baku",
        "amman", "petra", "beirut", "muscat", "doha", "manama", "kuwait", "shiraz",
        "isfahan", "tabriz", "perth", "hobart", "darwin", "cairns", "geelong", "ballarat",
        "bendigo", "dunedin", "nelson", "rotorua", "tauranga", "napier", "calgary",
        "edmonton", "regina", "halifax", "victoria", "kelowna", "kingston", "guelph",
        "portland", "boise", "tucson", "tacoma", "spokane", "fresno", "reno", "tulsa",
        "wichita", "omaha", "boulder", "asheville", "savannah", "tampa", "orlando",
        "sedona", "laramie", "bozeman", "helena", "juneau", "fairbanks", "bangor",
        "ithaca", "buffalo", "albany", "trenton", "newark", "salem", "eugene", "olympia",
        "mendoza", "rosario", "cordoba-ar", "salta", "bariloche", "valparaiso", "iquique",
        "cusco", "arequipa", "quito", "cuenca", "medellin", "cartagena", "cali", "manaus",
        "recife", "curitiba", "fortaleza", "natal", "belem", "salvador", "montevideo",
        "asuncion", "sucre", "potosi", "merida", "oaxaca", "puebla", "leon", "queretaro",
        "antigua", "granada-ni", "leon-ni", "panama", "medellin-co",
    ]

    /// A place name not already in `used`. Falls back to a numeric suffix once the
    /// list is exhausted within a project.
    public static func random(excluding used: Set<String>) -> String {
        let available = all.filter { !used.contains($0) }
        if let pick = available.randomElement() { return pick }
        let base = all.randomElement() ?? "workspace"
        var i = 2
        while used.contains("\(base)-\(i)") { i += 1 }
        return "\(base)-\(i)"
    }
}
