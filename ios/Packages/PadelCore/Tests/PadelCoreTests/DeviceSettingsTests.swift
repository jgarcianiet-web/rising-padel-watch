import XCTest
@testable import PadelCore

final class DeviceSettingsTests: XCTestCase {

    func testAplicaLosAjustesEntrantesSiSonMasRecientes() {
        let local = DeviceSettings(playerAlias: "viejo", updatedAtEpochMs: 1_000)
        let incoming = DeviceSettings(playerAlias: "nuevo", updatedAtEpochMs: 2_000)

        XCTAssertEqual(local.merged(with: incoming).playerAlias, "nuevo")
    }

    func testIgnoraLosAjustesEntrantesSiSonMasViejos() {
        let local = DeviceSettings(playerAlias: "reloj", updatedAtEpochMs: 5_000)
        let incoming = DeviceSettings(playerAlias: "movil", updatedAtEpochMs: 4_999)

        XCTAssertEqual(local.merged(with: incoming).playerAlias, "reloj")
    }

    func testConLaMismaMarcaDeTiempoGanaLoLocal() {
        let local = DeviceSettings(playerAlias: "reloj", updatedAtEpochMs: 7_000)
        let incoming = DeviceSettings(playerAlias: "movil", updatedAtEpochMs: 7_000)

        XCTAssertEqual(local.merged(with: incoming).playerAlias, "reloj")
    }

    /// El caso que motiva la marca de tiempo: `updateApplicationContext` reentrega el
    /// último estado al reconectar, así que sin ella una reconexión revive ajustes ya
    /// sustituidos.
    func testUnaReentregaDelMismoPayloadNoRevierteUnCambioPosterior() {
        let replicado = DeviceSettings(collectTrainingData: true, updatedAtEpochMs: 1_000)
        let local = DeviceSettings().merged(with: replicado)
        var editadoDespues = local
        editadoDespues.collectTrainingData = false
        editadoDespues.updatedAtEpochMs = 2_000

        let tras = editadoDespues.merged(with: replicado)

        XCTAssertFalse(tras.collectTrainingData)
        XCTAssertEqual(tras.updatedAtEpochMs, 2_000)
    }

    func testElAliasSeNormaliza() {
        XCTAssertEqual(DeviceSettings.sanitizeAlias("  Marta G  "), "marta-g")
        XCTAssertEqual(DeviceSettings.sanitizeAlias("JUAN"), "juan")
    }

    func testUnAliasVacioCaeAlValorPorDefecto() {
        XCTAssertEqual(DeviceSettings.sanitizeAlias(""), DeviceSettings.defaultAlias)
        XCTAssertEqual(DeviceSettings.sanitizeAlias("   "), DeviceSettings.defaultAlias)
    }

    func testElAliasSeAcota() {
        let alias = DeviceSettings.sanitizeAlias(String(repeating: "a", count: 100))
        XCTAssertEqual(alias.count, DeviceSettings.maxAliasLength)
    }

    func testElPayloadSobreviveALaIdaYVuelta() throws {
        let original = DeviceSettings(
            profile: PlayerProfile(hand: .left, watchWrist: .left, birthYear: 1990),
            sensitivity: .high,
            shareHealth: true,
            collectTrainingData: true,
            playerAlias: "marta",
            updatedAtEpochMs: 1_785_002_652_000
        )

        let data = try XCTUnwrap(DeviceSettings.encode(original))
        XCTAssertEqual(DeviceSettings.decode(data), original)
    }

    func testUnPayloadIlegibleDevuelveNilEnVezDeRomper() {
        XCTAssertNil(DeviceSettings.decode(Data("{no es json".utf8)))
        XCTAssertNil(DeviceSettings.decode(Data()))
    }

    /// Un iPhone con una versión más nueva no puede tumbar la replicación en el reloj.
    func testToleraCamposDesconocidosDeUnaVersionPosterior() {
        let json = #"{"playerAlias":"marta","updatedAtEpochMs":10,"campoFuturo":42}"#
        let decoded = DeviceSettings.decode(Data(json.utf8))

        XCTAssertEqual(decoded?.playerAlias, "marta")
    }

    /// Y un payload de una versión anterior, al que le faltan claves, tampoco.
    func testToleraCamposQueFaltanDeUnaVersionAnterior() {
        let decoded = DeviceSettings.decode(Data(#"{"updatedAtEpochMs":10}"#.utf8))

        XCTAssertEqual(decoded?.playerAlias, DeviceSettings.defaultAlias)
        XCTAssertEqual(decoded?.sensitivity, .medium)
        XCTAssertFalse(decoded?.shareHealth ?? true)
    }

    /// Los ajustes de partido son del reloj: replicarlos pisaría lo que acaba de elegir.
    func testElPayloadNoLlevaAjustesDeMarcadorNiCredenciales() throws {
        let data = try XCTUnwrap(DeviceSettings.encode(DeviceSettings()))
        let encoded = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(encoded.contains("trackScore"))
        XCTAssertFalse(encoded.contains("deuceFormat"))
        XCTAssertFalse(encoded.contains("token"))
        XCTAssertFalse(encoded.contains("baseURL"))
    }
}
