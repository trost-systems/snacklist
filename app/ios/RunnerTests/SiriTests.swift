import Intents
import UIKit
import XCTest

@testable import Runner

/// Answers every request of a session built with it; records the last request and its body.
final class StubProtocol: URLProtocol {
  enum Reply {
    case http(Int, String)
    case failure(URLError.Code)
  }

  static var reply: Reply = .http(500, "")
  static var requests: [(request: URLRequest, body: Data)] = []

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requests.append((request, Self.body(of: request)))
    switch Self.reply {
    case .failure(let code):
      client?.urlProtocol(self, didFailWithError: URLError(code))
    case .http(let status, let body):
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: ["content-type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}

  private static func body(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}

final class VoiceClientTests: XCTestCase {
  let credential = SiriCredential(
    token: "fgp_test", id: "c1", userId: "u1", sessionId: "s1",
    url: URL(string: "https://example.supabase.co/functions/v1/voice")!)

  override func setUp() {
    StubProtocol.requests = []
  }

  private func client(signedIn: Bool = true) -> VoiceClient {
    let config = VoiceClient.configuration()
    config.protocolClasses = [StubProtocol.self]
    let credential = signedIn ? self.credential : nil
    return VoiceClient(session: URLSession(configuration: config)) { credential }
  }

  private func send(
    _ reply: StubProtocol.Reply, mode: VoiceMode = .add, lang: VoiceLanguage = .en
  ) async -> VoiceResult {
    StubProtocol.reply = reply
    return await client().send(text: mode == .add ? "milk, eggs and bread" : nil, mode: mode, lang: lang)
  }

  func testTheRequestCarriesTokenTextModeAndLanguage() async throws {
    _ = await send(.http(200, #"{"outcome":"added","speech":"Added milk."}"#), lang: .de)
    let (request, body) = try XCTUnwrap(StubProtocol.requests.last)
    XCTAssertEqual(request.url, credential.url)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fgp_test")
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
    XCTAssertEqual(json, ["text": "milk, eggs and bread", "mode": "add", "lang": "de"])
  }

  func testTheRequestNamesTheBuildAndTheIntent() async throws {
    StubProtocol.reply = .http(200, #"{"outcome":"added","speech":"Added milk."}"#)
    var sender = client()
    sender.caller = "AddItems"
    _ = await sender.send(text: "milk", mode: .add, lang: .en)
    let header = try XCTUnwrap(StubProtocol.requests.last?.request.value(forHTTPHeaderField: "x-snacklist-client"))
    XCTAssertTrue(header.hasPrefix("ios-"), header)
    XCTAssertTrue(header.hasSuffix(".AddItems"), header)
    XCTAssertEqual(VoiceClient.clientHeader(caller: "Lists.add", info: ["CFBundleVersion": "1210"]), "ios-1210.Lists.add")
    XCTAssertEqual(VoiceClient.clientHeader(caller: "ReadList", info: nil), "ios-0.ReadList")
  }

  func testReadSendsNoText() async throws {
    _ = await send(.http(200, #"{"outcome":"read","speech":"Milk."}"#), mode: .read)
    let body = try XCTUnwrap(StubProtocol.requests.last?.body)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
    XCTAssertEqual(json, ["mode": "read", "lang": "en"])
  }

  func testTheWholeRequestGivesUpAfterEightSeconds() {
    let config = VoiceClient.configuration()
    XCTAssertEqual(config.timeoutIntervalForRequest, 8)
    XCTAssertEqual(config.timeoutIntervalForResource, 8)
    XCTAssertFalse(config.waitsForConnectivity)
  }

  func testWithoutACredentialNothingIsSent() async {
    let result = await client(signedIn: false).send(text: "milk", mode: .add, lang: .en)
    XCTAssertEqual(result, .failed(.notSignedIn))
    XCTAssertTrue(StubProtocol.requests.isEmpty)
  }

  func testSuccessNeedsTheServersOutcome() async {
    let added = await send(.http(200, #"{"outcome":"added","speech":"Added milk, eggs and bread to Snacklist."}"#))
    XCTAssertEqual(added, .added(speech: "Added milk, eggs and bread to Snacklist."))
    let already = await send(.http(200, #"{"outcome":"nothing_added","speech":"Already on the list: milk."}"#))
    XCTAssertEqual(already, .nothingAdded(speech: "Already on the list: milk."))
    let read = await send(.http(200, #"{"outcome":"read","speech":"Milk and eggs.","items":[],"total":2}"#), mode: .read)
    XCTAssertEqual(read, .read(speech: "Milk and eggs.", items: []))
  }

  func testAskAndConfirmedGoInTheRequestOnlyWhenSet() async throws {
    StubProtocol.reply = .http(200, #"{"outcome":"added","speech":"Added butter."}"#)
    _ = await client().send(text: "butter", mode: .add, lang: .en, ask: true)
    let asked = try XCTUnwrap(StubProtocol.requests.last?.body)
    let askJson = try XCTUnwrap(JSONSerialization.jsonObject(with: asked) as? [String: Any])
    XCTAssertEqual(askJson["ask"] as? Bool, true)
    XCTAssertNil(askJson["confirmed"])
    _ = await client().send(text: "butter", mode: .add, lang: .en, confirmed: true)
    let yes = try XCTUnwrap(StubProtocol.requests.last?.body)
    let yesJson = try XCTUnwrap(JSONSerialization.jsonObject(with: yes) as? [String: Any])
    XCTAssertEqual(yesJson["confirmed"] as? Bool, true)
    XCTAssertNil(yesJson["ask"])
  }

  func testANamedListGoesInTheRequestTrimmedAndOnlyWhenGiven() async throws {
    StubProtocol.reply = .http(200, #"{"outcome":"added","speech":"Added balloons."}"#)
    _ = await client().send(text: "balloons", mode: .add, lang: .en, list: " Birthday ")
    let named = try XCTUnwrap(StubProtocol.requests.last?.body)
    let namedJson = try XCTUnwrap(JSONSerialization.jsonObject(with: named) as? [String: Any])
    XCTAssertEqual(namedJson["list"] as? String, "Birthday")
    _ = await client().send(text: "balloons", mode: .add, lang: .en, list: "  ")
    let blank = try XCTUnwrap(StubProtocol.requests.last?.body)
    let blankJson = try XCTUnwrap(JSONSerialization.jsonObject(with: blank) as? [String: Any])
    XCTAssertNil(blankJson["list"], "a blank name is no list")
  }

  func testConfirmKeepsTheListTheServerUsed() async {
    let confirm = await send(.http(
      200,
      #"{"outcome":"confirm","speech":"s","question":"q","again":"butter","list":{"id":"l1","name":"Birthday"}}"#))
    XCTAssertEqual(confirm, .confirm(speech: "s", question: "q", again: "butter", list: "l1"))
  }

  func testConfirmCarriesTheQuestionAndWhatAYesSends() async {
    let confirm = await send(.http(
      200,
      #"{"outcome":"confirm","speech":"Already on the list: Butter Weihenstephan.","question":"Butter Weihenstephan is already on the list. Should I add butter anyway?","again":"butter"}"#))
    XCTAssertEqual(
      confirm,
      .confirm(
        speech: "Already on the list: Butter Weihenstephan.",
        question: "Butter Weihenstephan is already on the list. Should I add butter anyway?",
        again: "butter"))
    let noQuestion = await send(.http(200, #"{"outcome":"confirm","speech":"Already on the list: Butter Weihenstephan."}"#))
    XCTAssertEqual(noQuestion, .failed(.noAnswer))
    let confirmAsRead = await send(
      .http(200, #"{"outcome":"confirm","speech":"x","question":"y","again":"z"}"#), mode: .read)
    XCTAssertEqual(confirmAsRead, .failed(.noAnswer))
  }

  func testReadKeepsTheOpenItemsWithTheirQuantity() async {
    let read = await send(
      .http(200, #"{"outcome":"read","speech":"Milch, 2 kg Mehl.","items":[{"name":"Milch","quantity":null},{"name":"Mehl","quantity":"2 kg"}],"total":2}"#),
      mode: .read)
    XCTAssertEqual(read, .read(speech: "Milch, 2 kg Mehl.", items: ["Milch", "2 kg Mehl"]))
  }

  func testA200WithoutAKnownOutcomeIsNoSuccess() async {
    let cases = [
      #"{"speech":"Hinzugefügt: Milch."}"#,
      #"{"outcome":"parsed","speech":"Verstanden: Milch."}"#,
      #"{"outcome":"added"}"#,
      #"{"outcome":"added","speech":""}"#,
      "not json",
      "",
    ]
    for body in cases {
      let result = await send(.http(200, body))
      XCTAssertEqual(result, .failed(.noAnswer), body)
    }
    let readAsAdd = await send(.http(200, #"{"outcome":"read","speech":"Milk."}"#))
    XCTAssertEqual(readAsAdd, .failed(.noAnswer))
    let addAsRead = await send(.http(200, #"{"outcome":"added","speech":"Added milk."}"#), mode: .read)
    XCTAssertEqual(addAsRead, .failed(.noAnswer))
  }

  func testEachFailureCode() async {
    let cases: [(Int, String, VoiceFailure)] = [
      (401, #"{"outcome":"unauthorized","error":"unauthorized","speech":"x"}"#, .signedOut),
      (401, "", .signedOut),
      (403, #"{"outcome":"no_household","error":"no_household","speech":"x"}"#, .noHousehold),
      (400, #"{"outcome":"no_text","error":"no_text","speech":"x"}"#, .nothingUnderstood),
      (422, #"{"outcome":"nothing_understood","error":"nothing_understood","speech":"x"}"#, .nothingUnderstood),
      (413, #"{"outcome":"too_long","error":"too_long","speech":"x"}"#, .tooLong),
      (500, #"{"outcome":"server","error":"server","speech":"x"}"#, .server),
      (500, #"{"error":"server","speech":"x"}"#, .server),
      (502, "<html>Bad Gateway</html>", .noAnswer),
      (504, "", .noAnswer),
      (405, #"{"outcome":"method","error":"method","speech":"x"}"#, .noAnswer),
    ]
    for (status, body, failure) in cases {
      let result = await send(.http(status, body))
      XCTAssertEqual(result, .failed(failure), "\(status) \(body)")
    }
  }

  func testPremiumRequiredLocksAtAnyStatus() async {
    let speech = "Voice commands are part of Snacklist Premium. You can unlock it in the app under More, Snacklist Premium. I didn't add anything."
    for status in [200, 403, 402] {
      let result = await send(.http(status, #"{"outcome":"premium_required","error":"premium_required","speech":"\#(speech)"}"#))
      XCTAssertEqual(result, .lockedHousehold(speech: speech), "\(status)")
    }
    let bare = await send(.http(403, #"{"error":"premium_required"}"#))
    XCTAssertEqual(bare, .lockedHousehold(speech: nil))
  }

  func testNetworkFailures() async {
    let cases: [(URLError.Code, VoiceFailure)] = [
      (.notConnectedToInternet, .offline),
      (.cannotFindHost, .offline),
      (.cannotConnectToHost, .offline),
      (.dataNotAllowed, .offline),
      (.timedOut, .noAnswer),
      (.networkConnectionLost, .noAnswer),
      (.secureConnectionFailed, .noAnswer),
    ]
    for (code, failure) in cases {
      let result = await send(.failure(code))
      XCTAssertEqual(result, .failed(failure), "\(code)")
    }
  }
}

/// The SiriKit Lists handlers against a stubbed `voice` (a made-up credential, no real household).
final class SiriKitListsTests: XCTestCase {
  override func setUp() {
    StubProtocol.requests = []
  }

  private func client(signedIn: Bool = true) -> VoiceClient {
    let config = VoiceClient.configuration()
    config.protocolClasses = [StubProtocol.self]
    let credential = SiriCredential(
      token: "fgp_test", id: "c1", userId: "u1", sessionId: "s1",
      url: URL(string: "https://example.supabase.co/functions/v1/voice")!)
    return VoiceClient(session: URLSession(configuration: config)) { signedIn ? credential : nil }
  }

  private func addTasks(_ titles: [String]?) -> INAddTasksIntent {
    INAddTasksIntent(
      targetTaskList: INTaskList(
        title: INSpeakableString(spokenPhrase: "Einkaufsliste"), tasks: [], groupName: nil,
        createdDateComponents: nil, modifiedDateComponents: nil, identifier: nil),
      taskTitles: titles?.map { INSpeakableString(spokenPhrase: $0) },
      spatialEventTrigger: nil, temporalEventTrigger: nil, priority: .notFlagged)
  }

  private func lastBody() throws -> [String: String] {
    let body = try XCTUnwrap(StubProtocol.requests.last?.body)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
  }

  func testTheTitlesGoToVoiceAsOneSentence() async throws {
    StubProtocol.reply = .http(200, #"{"outcome":"added","speech":"Hinzugefügt: Zahnpasta, Brot."}"#)
    let response = await AddTasksHandler(client: client())
      .respond(to: addTasks(["Zahnpasta", " Brot ", ""]))
    let body = try lastBody()
    XCTAssertEqual(body["text"], "Zahnpasta, Brot")
    XCTAssertEqual(body["mode"], "add")
    XCTAssertNotNil(body["lang"], "the language follows the text (VoiceLanguage)")
    XCTAssertEqual(response.code, .success)
    XCTAssertEqual(response.addedTasks?.map(\.title.spokenPhrase), ["Zahnpasta", "Brot"])
  }

  func testTheTargetListGoesToVoiceByName() async throws {
    StubProtocol.reply = .http(200, #"{"outcome":"added","speech":"Hinzugefügt auf Geburtstag: Luftballons."}"#)
    let intent = INAddTasksIntent(
      targetTaskList: INTaskList(
        title: INSpeakableString(spokenPhrase: "Geburtstag"), tasks: [], groupName: nil,
        createdDateComponents: nil, modifiedDateComponents: nil, identifier: nil),
      taskTitles: [INSpeakableString(spokenPhrase: "Luftballons")],
      spatialEventTrigger: nil, temporalEventTrigger: nil, priority: .notFlagged)
    let response = await AddTasksHandler(client: client()).respond(to: intent)
    XCTAssertEqual(try lastBody()["list"], "Geburtstag")
    XCTAssertEqual(response.code, .success)
    XCTAssertEqual(AddTasksHandler.listName(addTasks(["Milch"])), "Einkaufsliste")
    let noList = INAddTasksIntent(
      targetTaskList: nil, taskTitles: [INSpeakableString(spokenPhrase: "Milch")],
      spatialEventTrigger: nil, temporalEventTrigger: nil, priority: .notFlagged)
    XCTAssertNil(AddTasksHandler.listName(noList))
  }

  func testAlreadyOnTheListIsStillASuccess() async {
    StubProtocol.reply = .http(200, #"{"outcome":"nothing_added","speech":"Schon auf der Liste: Milch."}"#)
    let response = await AddTasksHandler(client: client()).respond(to: addTasks(["Milch"]))
    XCTAssertEqual(response.code, .success)
  }

  private let failures: [StubProtocol.Reply] = [
    .http(401, ""),
    .http(403, #"{"outcome":"no_household","error":"no_household","speech":"x"}"#),
    .http(403, #"{"outcome":"premium_required","error":"premium_required","speech":"x"}"#),
    .http(500, #"{"outcome":"server","error":"server","speech":"x"}"#),
    .http(200, #"{"outcome":"parsed","speech":"Verstanden: Milch."}"#),
    .failure(.notConnectedToInternet),
    .failure(.timedOut),
  ]

  /// Siri answers a failure in its sheet; only `.failureRequiringAppLaunch` would open the app.
  func testEveryAddFailureStaysInSiri() async {
    for reply in failures {
      StubProtocol.reply = reply
      let response = await AddTasksHandler(client: client()).respond(to: addTasks(["Milch"]))
      XCTAssertEqual(response.code, .failure, "\(reply)")
      XCTAssertNil(response.addedTasks, "\(reply)")
    }
    let signedOut = await AddTasksHandler(client: client(signedIn: false)).respond(to: addTasks(["Milch"]))
    XCTAssertEqual(signedOut.code, .failure)
    XCTAssertEqual(StubProtocol.requests.count, failures.count, "signed out sends nothing")
  }

  func testEveryReadFailureStaysInSiri() async {
    for reply in failures {
      StubProtocol.reply = reply
      let response = await SearchTasksHandler(client: client()).respond()
      XCTAssertEqual(response.code, .failure, "\(reply)")
      XCTAssertNil(response.tasks, "\(reply)")
    }
    let signedOut = await SearchTasksHandler(client: client(signedIn: false)).respond()
    XCTAssertEqual(signedOut.code, .failure)
  }

  func testEachSpokenTitleResolvesAndNoneMeansAsk() {
    let handler = AddTasksHandler(client: client())
    let resolved = expectation(description: "titles resolved")
    handler.resolveTaskTitles(for: addTasks(["Zahnpasta", "", "Brot"])) { results in
      XCTAssertEqual(results.count, 2)
      resolved.fulfill()
    }
    let asked = expectation(description: "no titles")
    handler.resolveTaskTitles(for: addTasks(nil)) { results in
      XCTAssertEqual(results.count, 1, "one needsValue: Siri asks what to add")
      asked.fulfill()
    }
    wait(for: [resolved, asked], timeout: 1)
  }

  func testSearchReadsTheOpenItemsAsTasks() async throws {
    StubProtocol.reply = .http(
      200, #"{"outcome":"read","speech":"Milch, 2 kg Mehl.","items":[{"name":"Milch","quantity":null},{"name":"Mehl","quantity":"2 kg"}],"total":2}"#)
    let response = await SearchTasksHandler(client: client()).respond()
    XCTAssertEqual(try lastBody()["mode"], "read")
    XCTAssertNil(try lastBody()["text"])
    XCTAssertEqual(response.code, .success)
    XCTAssertEqual(response.tasks?.map(\.title.spokenPhrase), ["Milch", "2 kg Mehl"])
    XCTAssertEqual(response.taskLists?.first?.tasks.count, 2)
  }

  @MainActor
  func testTheAppHandsOutBothHandlers() throws {
    let delegate = try XCTUnwrap(UIApplication.shared.delegate as? AppDelegate)
    let selector = #selector(UIApplicationDelegate.application(_:handlerFor:))
    XCTAssertTrue(delegate.responds(to: selector), "iOS finds the handler through the selector")
    XCTAssertTrue(delegate.application(.shared, handlerFor: addTasks(["Milch"])) is AddTasksHandler)
    XCTAssertTrue(delegate.application(.shared, handlerFor: INSearchForNotebookItemsIntent()) is SearchTasksHandler)
    XCTAssertNil(delegate.application(.shared, handlerFor: INSendMessageIntent()))
    let supported = Bundle.main.object(forInfoDictionaryKey: "INIntentsSupported") as? [String]
    XCTAssertEqual(Set(supported ?? []), ["INAddTasksIntent", "INSearchForNotebookItemsIntent"])
  }
}

final class SiriAnswerTests: XCTestCase {
  func testEveryAddFailureSaysNothingWasAdded() {
    for lang in VoiceLanguage.allCases {
      let copy = SiriCopy(lang)
      for failure in VoiceFailure.allCases where failure != .noAnswer {
        let answer = VoiceResult.failed(failure).answer(mode: .add, copy: copy)
        XCTAssertTrue(answer.hasSuffix(copy[.nothingAdded]), "\(lang) \(failure): \(answer)")
      }
      let unknown = VoiceResult.failed(.noAnswer).answer(mode: .add, copy: copy)
      XCTAssertTrue(unknown.hasSuffix(copy[.notConfirmed]), "\(lang): \(unknown)")
    }
  }

  func testTheExactSentences() {
    let en = SiriCopy(.en), de = SiriCopy(.de)
    XCTAssertEqual(
      VoiceResult.failed(.signedOut).answer(mode: .add, copy: en),
      "Open Snacklist and sign in again. I didn't add anything.")
    XCTAssertEqual(
      VoiceResult.failed(.notSignedIn).answer(mode: .add, copy: de),
      "Öffne Snacklist und melde dich an. Ich habe nichts hinzugefügt.")
    XCTAssertEqual(
      VoiceResult.failed(.offline).answer(mode: .add, copy: en),
      "Snacklist can't reach the internet right now. I didn't add anything.")
    XCTAssertEqual(
      VoiceResult.failed(.offline).answer(mode: .read, copy: de),
      "Snacklist hat gerade keine Internetverbindung. Ich konnte deine Liste nicht vorlesen.")
    XCTAssertEqual(
      VoiceResult.added(speech: "Added milk to Snacklist.").answer(mode: .add, copy: en),
      "Added milk to Snacklist.")
  }

  func testANoToTheQuestionSaysWhatIsOnTheList() {
    let confirm = VoiceResult.confirm(
      speech: "Schon auf der Liste: Butter Weihenstephan.",
      question: "Butter Weihenstephan steht schon drauf. Soll ich Butter trotzdem dazuschreiben?",
      again: "Butter")
    XCTAssertEqual(
      confirm.answer(mode: .add, copy: SiriCopy(.de)), "Schon auf der Liste: Butter Weihenstephan.")
  }

  func testALockedHouseholdHearsTheServerOrThePlaceholder() {
    let en = SiriCopy(.en), de = SiriCopy(.de)
    XCTAssertEqual(
      VoiceResult.lockedHousehold(speech: "Server words.").answer(mode: .add, copy: en),
      "Server words.")
    XCTAssertEqual(
      VoiceResult.lockedHousehold(speech: nil).answer(mode: .add, copy: de),
      "Sprachbefehle sind Teil von Snacklist Premium. Du kannst es in der App freischalten. Ich habe nichts hinzugefügt.")
    XCTAssertEqual(
      VoiceResult.lockedHousehold(speech: nil).answer(mode: .add, copy: en),
      "Voice commands are part of Snacklist Premium. You can unlock it in the app under More, Snacklist Premium. I didn't add anything.")
  }

  func testEveryKeyIsTranslatedInBothLanguages() {
    let en = SiriCopy(.en), de = SiriCopy(.de)
    for key in SiriCopy.Key.allCases {
      XCTAssertNotEqual(en[key], key.rawValue, "en lacks \(key.rawValue)")
      XCTAssertNotEqual(de[key], key.rawValue, "de lacks \(key.rawValue)")
      XCTAssertNotEqual(en[key], de[key], "de is untranslated: \(key.rawValue)")
    }
  }

  func testDictatedTextPicksTheLanguage() {
    XCTAssertEqual(VoiceLanguage.of("Milch, Eier und Brot", localizations: ["en"]), .de)
    XCTAssertEqual(VoiceLanguage.of("milk, eggs and bread", localizations: ["de"]), .en)
    XCTAssertEqual(VoiceLanguage.of("zwei Gurken und eine Packung Eier", localizations: ["en"]), .de)
    XCTAssertEqual(VoiceLanguage.of("two cucumbers and a pack of eggs", localizations: ["de"]), .en)
  }

  func testWithoutClearTextTheAppsLocalizationDecides() {
    XCTAssertEqual(VoiceLanguage.of(nil, localizations: ["de"]), .de)
    XCTAssertEqual(VoiceLanguage.of("", localizations: ["de-AT", "en"]), .de)
    XCTAssertEqual(VoiceLanguage.of(nil, localizations: ["en"]), .en)
    XCTAssertEqual(VoiceLanguage.of(nil, localizations: ["fr"]), .en)
    XCTAssertEqual(VoiceLanguage.of(nil, localizations: []), .en)
    let oneWord = VoiceLanguage.of("Milch", localizations: ["en"])
    XCTAssertTrue([.de, .en].contains(oneWord), "one word may go either way")
  }
}

final class SiriStoreTests: XCTestCase {
  let store = SiriCredentialStore(service: "com.snacklist.app.siri.tests")

  override func tearDown() {
    store.clear()
  }

  func testTheKeychainRoundTrip() throws {
    XCTAssertNil(store.load())
    let first = SiriCredential(
      token: "fgp_one", id: "c1", userId: "u1", sessionId: "s1",
      url: URL(string: "https://example.supabase.co/functions/v1/voice")!)
    try store.save(first)
    XCTAssertEqual(store.load(), first)
    let second = SiriCredential(
      token: "fgp_two", id: "c2", userId: "u1", sessionId: "s2",
      url: URL(string: "http://127.0.0.1:57421/functions/v1/voice")!)
    try store.save(second)
    XCTAssertEqual(store.load(), second, "store overwrites")
    store.clear()
    XCTAssertNil(store.load())
  }

  func testTheItemIsOnlyReadableOnThisDeviceAfterFirstUnlock() throws {
    try store.save(SiriCredential(
      token: "fgp_one", id: "c1", userId: "u1", sessionId: "s1",
      url: URL(string: "https://example.supabase.co/functions/v1/voice")!))
    var found: CFTypeRef?
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: store.service,
      kSecAttrAccount as String: "credential",
      kSecReturnAttributes as String: true,
    ]
    XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &found), errSecSuccess)
    let attributes = try XCTUnwrap(found as? [String: Any])
    XCTAssertEqual(
      attributes[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
  }

  func testChannelArgumentsNeedEveryField() {
    let full: [String: Any] = [
      "token": "fgp_x", "id": "c", "userId": "u", "sessionId": "s",
      "url": "https://example.supabase.co/functions/v1/voice",
    ]
    XCTAssertNotNil(SiriCredential(arguments: full))
    for key in full.keys {
      var missing = full
      missing.removeValue(forKey: key)
      XCTAssertNil(SiriCredential(arguments: missing), "without \(key)")
    }
    var ftp = full
    ftp["url"] = "ftp://example.com/voice"
    XCTAssertNil(SiriCredential(arguments: ftp))
    XCTAssertNil(SiriCredential(arguments: nil))
  }

  private func suggestionStore() -> ItemSuggestionStore {
    ItemSuggestionStore(
      file: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathComponent("suggestions.json"))
  }

  func testSuggestionsAreTrimmedDedupedAndCapped() {
    let suggestions = suggestionStore()
    XCTAssertEqual(suggestions.entries(), [])
    suggestions.save(
      [" Milch ", "milch", "", "Eier"].map { ItemSuggestionStore.Entry(name: $0) }
        + (1...60).map { ItemSuggestionStore.Entry(name: "Item \($0)") })
    let names = suggestions.entries().map(\.name)
    XCTAssertEqual(Array(names.prefix(2)), ["Milch", "Eier"])
    XCTAssertEqual(names.count, 50)
    suggestions.clear()
    XCTAssertEqual(suggestions.entries(), [])
  }

  func testSynonymsAreCappedAndNeverRepeatAName() {
    let suggestions = suggestionStore()
    suggestions.save([
      .init(name: "Karotten", synonyms: ["Möhren", " Milch ", "Mohrrüben", "Gelbe Rüben"]),
      .init(name: "Milch", synonyms: ["möhren"]),
    ])
    XCTAssertEqual(suggestions.entries(), [
      .init(name: "Karotten", synonyms: ["Möhren", "Mohrrüben"]),
      .init(name: "Milch"),
    ])
    suggestions.save((1...50).map { ItemSuggestionStore.Entry(name: "Item \($0)", synonyms: ["A \($0)", "B \($0)"]) })
    let spoken = suggestions.entries().reduce(0) { $0 + 1 + $1.synonyms.count }
    XCTAssertEqual(spoken, ItemSuggestionStore.spokenLimit, "Apple's 1,000 phrases with six item phrases")
  }

  func testAFileFromBeforeSynonymsStillReads() throws {
    let suggestions = suggestionStore()
    try FileManager.default.createDirectory(
      at: suggestions.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"["Milch","Eier"]"#.utf8).write(to: suggestions.file)
    XCTAssertEqual(suggestions.entries(), [.init(name: "Milch"), .init(name: "Eier")])
  }

  func testTheChannelArgumentsBecomeEntries() {
    XCTAssertEqual(
      ItemSuggestionStore.Entry(argument: ["name": "Karotten", "synonyms": ["Möhren"]]),
      .init(name: "Karotten", synonyms: ["Möhren"]))
    XCTAssertEqual(ItemSuggestionStore.Entry(argument: ["name": "Brot"]), .init(name: "Brot"))
    XCTAssertNil(ItemSuggestionStore.Entry(argument: ["synonyms": ["Möhren"]]))
    XCTAssertNil(ItemSuggestionStore.Entry(argument: "Brot"))
  }

  func testASynonymFindsItsItem() async throws {
    let store = suggestionStore()
    store.save([.init(name: "Karotten", synonyms: ["Möhren"]), .init(name: "Milch")])
    let query = ItemSuggestionQuery(store: store)
    let found = try await query.entities(matching: "möhren")
    XCTAssertEqual(found.map(\.id), ["Karotten"], "the household's own name goes to voice")
    let byId = try await query.entities(for: ["Karotten"])
    XCTAssertEqual(byId.first?.synonyms, ["Möhren"])
    let suggested = try await query.suggestedEntities()
    XCTAssertEqual(suggested.map(\.id), ["Karotten", "Milch"])
  }
}

final class OpenListIntentTests: XCTestCase {
  func testItOpensTheListTheWayAWidgetTapDoes() {
    XCTAssertEqual(OpenListIntent.list.absoluteString, "snacklist-widget://open/?homeWidget")
    let schemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
      .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    XCTAssertTrue(schemes.contains("snacklist-widget"), "the app answers its own link")
  }

  @available(*, deprecated)
  func testItIsTheOnlyIntentThatBringsTheAppForward() {
    XCTAssertTrue(OpenListIntent.openAppWhenRun)
    XCTAssertFalse(AddItemsIntent.openAppWhenRun)
    XCTAssertFalse(ReadListIntent.openAppWhenRun)
  }
}

/// The phrases in SnacklistShortcuts against Runner/AppShortcuts.xcstrings (job 97): each one has en
/// and de variants that name the app once and keep its one parameter.
final class AppShortcutPhraseTests: XCTestCase {
  private let runner = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Runner")

  private func intentsSource() throws -> String {
    try String(contentsOf: runner.appendingPathComponent("AppIntents/SnacklistIntents.swift"), encoding: .utf8)
  }

  private func codePhrases() throws -> [String] {
    try phrases(in: intentsSource())
  }

  private func phrases(in source: String) throws -> [String] {
    let literal = try NSRegularExpression(pattern: #""([^"\n]*\\\(\.applicationName\)[^"\n]*)""#)
    let range = NSRange(source.startIndex..., in: source)
    return literal.matches(in: source, range: range).map {
      String(source[Range($0.range(at: 1), in: source)!])
        .replacingOccurrences(of: #"\(.applicationName)"#, with: "${applicationName}")
        .replacingOccurrences(of: #"\(\.$item)"#, with: "${item}")
    }
  }

  private func placeholders(_ phrase: String) -> [String] {
    let pattern = try! NSRegularExpression(pattern: #"\$\{[A-Za-z]+\}"#)
    let range = NSRange(phrase.startIndex..., in: phrase)
    return pattern.matches(in: phrase, range: range).map { String(phrase[Range($0.range, in: phrase)!]) }.sorted()
  }

  /// The phrase sets per language of Runner/AppShortcuts.xcstrings, by Swift phrase.
  private func catalog(_ lang: String) throws -> [String: [String]] {
    struct Catalog: Decodable {
      struct Entry: Decodable { let localizations: [String: Localization] }
      struct Localization: Decodable {
        let stringSet: StringSet?
        let stringUnit: StringUnit?
      }
      struct StringSet: Decodable { let values: [String] }
      struct StringUnit: Decodable { let value: String }
      let strings: [String: Entry]
    }
    let data = try Data(contentsOf: runner.appendingPathComponent("AppShortcuts.xcstrings"))
    // Phrases are stringSets; a negative phrase is one stringUnit (job 170).
    return try JSONDecoder().decode(Catalog.self, from: data).strings
      .mapValues { entry in
        let localization = entry.localizations[lang]
        return localization?.stringSet?.values ?? localization?.stringUnit.map { [$0.value] } ?? []
      }
  }

  func testEveryPhraseHasEnglishAndGermanVariantsThatNameTheApp() throws {
    let phrases = try codePhrases()
    XCTAssertGreaterThanOrEqual(phrases.count, 3)
    for phrase in phrases {
      XCTAssertLessThanOrEqual(placeholders(phrase).filter { $0 != "${applicationName}" }.count, 1, phrase)
    }
    for lang in ["en", "de"] {
      let sets = try catalog(lang)
      for phrase in phrases {
        let values = sets[phrase] ?? []
        XCTAssertFalse(values.isEmpty, "\(lang) has no phrases for \(phrase)")
        for value in values {
          XCTAssertEqual(value.components(separatedBy: "${applicationName}").count, 2, "\(lang): \(value)")
          XCTAssertEqual(placeholders(value), placeholders(phrase), "\(lang): \(value)")
        }
      }
      let all = phrases.flatMap { sets[$0] ?? [] }.map { $0.lowercased() }
      XCTAssertEqual(Set(all).count, all.count, "\(lang) says no phrase twice")
    }
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: runner.appendingPathComponent("de.lproj/AppShortcuts.strings").path),
      "the catalog replaced the .strings tables")
  }

  func testTheNegativePhrasesNeverNameTheApp() throws {
    let source = try intentsSource()
    let start = try XCTUnwrap(source.range(of: "static var negativePhrases"))
    let end = try XCTUnwrap(source.range(of: "\n  }\n", range: start.upperBound..<source.endIndex))
    let block = String(source[start.upperBound..<end.lowerBound])
    let negatives = try NSRegularExpression(pattern: #""([^"\n]+)""#)
      .matches(in: block, range: NSRange(block.startIndex..., in: block))
      .map { String(block[Range($0.range(at: 1), in: block)!]) }
    XCTAssertFalse(negatives.isEmpty)
    for lang in ["en", "de"] {
      let sets = try catalog(lang)
      for negative in negatives {
        let values = try XCTUnwrap(sets[negative], "\(lang) lacks the negative \(negative)")
        XCTAssertFalse(values.isEmpty, negative)
        for value in values {
          XCTAssertFalse(value.lowercased().contains("snacklist") || value.contains("${applicationName}"), value)
        }
      }
    }
  }

  func testEachLanguageNamesTheAppTheWaySiriWritesIt() throws {
    let entries = try XCTUnwrap(
      Bundle.main.object(forInfoDictionaryKey: "INAlternativeAppNames") as? [[String: String]])
    let variables = entries.compactMap { $0["INAlternativeAppName"] }
    XCTAssertEqual(variables.count, entries.count)
    XCTAssertTrue((1...3).contains(variables.count), "Apple reads one to three")
    var names: [String: [String]] = [:]
    for lang in ["en", "de"] {
      let path = try XCTUnwrap(
        Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: lang),
        "the app ships \(lang).lproj/InfoPlist.strings")
      let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], lang)
      names[lang] = try variables.map { try XCTUnwrap(table[$0], "\(lang) lacks \($0)") }
    }
    for name in names.values.joined() {
      XCTAssertNotEqual(name.lowercased(), "snack", "the brand is never Snack alone")
    }
    for name in names["de"]! {
      XCTAssertFalse(name.lowercased().hasSuffix("liste"), "\(name): „zur … Liste“ is Reminders' grammar (job 97)")
    }
  }

  private func table(_ name: String, _ lang: String) throws -> [String: String] {
    let path = try XCTUnwrap(
      Bundle.main.path(forResource: name, ofType: "strings", inDirectory: nil, forLocalization: lang),
      "the app ships \(lang).lproj/\(name).strings")
    return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], lang)
  }

  /// German Siri hands "Füge X zur <…>liste hinzu" and "Einkaufsliste" to Reminders, and a bare
  /// "Auf meine Snacklist" is a fragment of that grammar (jobs 92, 97).
  func testGermanPhrasesStayOutOfRemindersGrammar() throws {
    let prepositions: Set<String> = ["auf", "zu", "zur", "zum", "in", "im", "an", "mit", "für"]
    let sets = try catalog("de")
    for phrase in try codePhrases().flatMap({ sets[$0] ?? [] }) {
      XCTAssertTrue(phrase.contains("${applicationName}"), phrase)
      XCTAssertFalse(phrase.lowercased().contains("liste"), phrase)
      let first = phrase.split(separator: " ").first.map { $0.lowercased() } ?? ""
      if prepositions.contains(first) {
        XCTAssertFalse(phrase.hasSuffix("${applicationName}"), "\(phrase) is a fragment without a verb")
      }
    }
  }

  /// Siri asks for the items after a phrase without one, which works for any item; an item phrase
  /// matches only the names the app suggested.
  func testAddPhrasesWithoutAnItemComeFirst() throws {
    let source = try intentsSource()
    let start = try XCTUnwrap(source.range(of: "intent: AddItemsIntent()"))
    let end = try XCTUnwrap(source.range(of: "shortTitle:", range: start.upperBound..<source.endIndex))
    let add = try phrases(in: String(source[start.upperBound..<end.lowerBound]))
    let withItem = add.map { $0.contains("${item}") }
    XCTAssertEqual(withItem.first, false)
    XCTAssertEqual(withItem, withItem.sorted { !$0 && $1 }, "\(add)")
  }

  func testEveryAlternativeNameHasAPronunciationHint() throws {
    let entries = try XCTUnwrap(
      Bundle.main.object(forInfoDictionaryKey: "INAlternativeAppNames") as? [[String: String]])
    XCTAssertLessThanOrEqual(entries.count, 3)
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleSpokenName") as? String, "Snacklist")
    for lang in ["en", "de", "Base"] {
      let strings = try table("InfoPlist", lang)
      for entry in entries {
        let hint = try XCTUnwrap(entry["INAlternativeAppNamePronunciationHint"], "\(entry)")
        XCTAssertFalse((strings[hint] ?? "").isEmpty, "\(lang) lacks \(hint)")
      }
      XCTAssertEqual(strings["CFBundleSpokenName"], "Snacklist", lang)
      XCTAssertFalse((strings["NSSiriUsageDescription"] ?? "").isEmpty, "\(lang) lacks NSSiriUsageDescription")
    }
  }

  func testAddReadAndOpenAreTheAppShortcuts() throws {
    let source = try intentsSource()
    let count = source.components(separatedBy: "AppShortcut(\n").count - 1
    XCTAssertEqual(count, 3)
    XCTAssertEqual(SnacklistShortcuts.appShortcuts.count, 3, "Apple allows at most ten")
    for intent in ["AddItemsIntent()", "ReadListIntent()", "OpenListIntent()"] {
      XCTAssertTrue(source.contains("intent: \(intent)"), intent)
    }
  }

  func testTheAppShipsGermanAndEnglishStrings() {
    let main = Bundle.main
    let lprojs = (try? FileManager.default.contentsOfDirectory(atPath: main.bundlePath))?
      .filter { $0.hasSuffix(".lproj") } ?? []
    for lang in ["en", "de"] {
      XCTAssertNotNil(
        main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: lang),
        "\(lang) Localizable; bundle has \(lprojs)")
    }
  }
}

/// "Use with Siri" is asked whenever the app comes forward unanswered, not only when the app
/// stores a new credential (job 467). The test host's AppDelegate observes the notification.
final class SiriAuthorizationTests: XCTestCase {
  private let status = SiriAuthorization.status
  private let request = SiriAuthorization.request

  override func tearDown() {
    SiriAuthorization.status = status
    SiriAuthorization.request = request
  }

  private func asks(_ status: INSiriAuthorizationStatus, when act: () -> Void) -> Bool {
    var asked = false
    SiriAuthorization.status = { status }
    SiriAuthorization.request = { asked = true }
    act()
    return asked
  }

  func testComingForwardAsksWhileUnanswered() {
    let active = { NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil) }
    XCTAssertTrue(asks(.notDetermined, when: active))
    for answered: INSiriAuthorizationStatus in [.authorized, .denied, .restricted] {
      XCTAssertFalse(asks(answered, when: active), "status \(answered.rawValue)")
    }
  }
}
